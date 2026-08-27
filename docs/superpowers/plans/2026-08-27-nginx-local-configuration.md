# Nginx Local Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom Nginx site configuration with a complete, read-only local snapshot of the official configuration and recreate an HTTP-only service that serves the official welcome page.

**Architecture:** Copy the full `/etc/nginx` tree byte-for-byte from the pinned `nginx:1.30.4-trixie` image into `setup/nginx/conf/`, including the `modules` symbolic link. Mount that directory at `/etc/nginx:ro`, publish only host port 80, and leave the official `/usr/share/nginx/html` content inside the image.

**Tech Stack:** Docker Engine or Docker Desktop, Docker Compose v2.17.2+, `nginx:1.30.4-trixie`, POSIX shell, `jq`, `curl`, Git

**Spec:** `docs/superpowers/specs/2026-08-27-nginx-local-configuration-design.md`

## Global Constraints

- Keep `image: nginx:1.30.4-trixie`; do not add a Dockerfile or build stanza.
- Store the official configuration snapshot under `setup/nginx/conf/` and mount it read-only at `/etc/nginx`.
- Publish only `"80:80"`, which binds the host port on all interfaces.
- Remove all domain redirects, TLS, static aliases, and uWSGI behavior by deleting `upstream.conf`.
- Keep `setup/nginx/html`, `setup/nginx/media`, `setup/nginx/ssl`, and `setup/nginx/static` on disk but do not mount them.
- Keep the Nginx restart policy, health check, logging, timezone, and Compose network unchanged.
- Do not change or restart any non-Nginx service.
- Use the image-owned `/usr/share/nginx/html`; do not add a local web-root mount.

---

### Task 1: Track the Complete Official Nginx Configuration

**Files:**
- Delete: `setup/nginx/conf/upstream.conf`
- Create: `setup/nginx/conf/nginx.conf`
- Create: `setup/nginx/conf/mime.types`
- Create: `setup/nginx/conf/fastcgi_params`
- Create: `setup/nginx/conf/scgi_params`
- Create: `setup/nginx/conf/uwsgi_params`
- Create: `setup/nginx/conf/conf.d/default.conf`
- Create symbolic link: `setup/nginx/conf/modules` -> `/usr/lib/nginx/modules`

**Interfaces:**
- Consumes: the unmodified `/etc/nginx` tree from `nginx:1.30.4-trixie`.
- Produces: a local configuration tree that can be mounted directly at `/etc/nginx:ro`.

- [ ] **Step 1: Run the structural check and verify it fails against the custom configuration**

Run:

```bash
sh -eu -c '
test ! -e setup/nginx/conf/upstream.conf
test -f setup/nginx/conf/nginx.conf
test -f setup/nginx/conf/mime.types
test -f setup/nginx/conf/fastcgi_params
test -f setup/nginx/conf/scgi_params
test -f setup/nginx/conf/uwsgi_params
test -f setup/nginx/conf/conf.d/default.conf
test -L setup/nginx/conf/modules
test "$(readlink setup/nginx/conf/modules)" = /usr/lib/nginx/modules
'
```

Expected: exit 1 because `upstream.conf` still exists and the official files are absent.

- [ ] **Step 2: Confirm the task-owned temporary container name is unused**

Run:

```bash
docker ps -a --filter 'name=^/codex-nginx-config-source$' --format '{{.Names}}'
```

Expected: no output. If the exact name exists, inspect it and stop rather than deleting a container not created by this execution.

- [ ] **Step 3: Delete the obsolete custom configuration**

Delete `setup/nginx/conf/upstream.conf` with `apply_patch`. Do not delete or modify any sibling Nginx content or certificate directory.

- [ ] **Step 4: Export the untouched configuration tree from the pinned image**

Run these commands in order:

```bash
docker create --name codex-nginx-config-source nginx:1.30.4-trixie
docker cp codex-nginx-config-source:/etc/nginx/. setup/nginx/conf/
docker rm codex-nginx-config-source
```

Expected: the create command returns a container ID, the copy succeeds, and the remove command prints `codex-nginx-config-source`. The container is created but never started, so the image entrypoint cannot modify `default.conf` before export.

- [ ] **Step 5: Run the structural check and verify it passes**

Run the exact shell check from Step 1 again.

Expected: exit 0 with no output.

Then run:

```bash
find setup/nginx/conf -mindepth 1 -maxdepth 2 -print | sort
```

Expected entries:

```text
setup/nginx/conf/conf.d
setup/nginx/conf/conf.d/default.conf
setup/nginx/conf/fastcgi_params
setup/nginx/conf/mime.types
setup/nginx/conf/modules
setup/nginx/conf/nginx.conf
setup/nginx/conf/scgi_params
setup/nginx/conf/uwsgi_params
```

- [ ] **Step 6: Verify every copied file against the pinned image**

Run:

```bash
shasum -a 256 \
  setup/nginx/conf/nginx.conf \
  setup/nginx/conf/mime.types \
  setup/nginx/conf/fastcgi_params \
  setup/nginx/conf/scgi_params \
  setup/nginx/conf/uwsgi_params \
  setup/nginx/conf/conf.d/default.conf
readlink setup/nginx/conf/modules
```

Expected hashes by file:

```text
4dee6b0c7c8278f6a9b827261c25d3215c9ea8955e41ff7fe3eabdd5297edce7  nginx.conf
6f95d1d7d75e3c072907d845622a69d23110d1266c16ff122b3109b8b21f3ae9  mime.types
f37852d0113de30fa6bfc3d9b180ef99383c06739530dd482a8538503afd5a58  fastcgi_params
f27b2027c571ccafcfb0fbb3f54d7aeee11a984e3a0f5a1fdf14629030fc9011  scgi_params
015cb581c2eb84b1a1ac9b575521d5881f791f632bfa62f34b26ba97d70c0d4f  uwsgi_params
48801b39b849818cd0a79221fa1e2b60aa198453368fdd46071d4b9883f5777c  conf.d/default.conf
/usr/lib/nginx/modules
```

The paths printed by `shasum` are longer than the labels above; compare each hash to its matching basename.

- [ ] **Step 7: Validate the local tree inside the official image**

Run:

```bash
docker run --rm \
  -v "$PWD/setup/nginx/conf:/etc/nginx:ro" \
  nginx:1.30.4-trixie nginx -t
```

Expected: `syntax is ok` and `test is successful`. The entrypoint may log that it cannot modify read-only `default.conf`; that message is informational.

- [ ] **Step 8: Commit the official configuration snapshot**

Run:

```bash
git add setup/nginx/conf
git diff --cached --check
git diff --cached --name-status
git commit -m "Track official Nginx configuration"
```

Expected staged changes: delete `upstream.conf`, add six regular configuration files and the `modules` symbolic link, with no other files staged.

---

### Task 2: Use the Full Configuration Mount and Recreate Nginx

**Files:**
- Modify: `docker-compose.yml:8-30`
- Modify: `README.md:5-70`
- Modify: `README.md:177-186`

**Interfaces:**
- Consumes: the complete `setup/nginx/conf/` tree produced by Task 1.
- Produces: an HTTP-only Nginx Compose service serving the image-owned default site on all host interfaces.

- [ ] **Step 1: Run the rendered-Compose assertion and verify it fails**

Run:

```bash
docker compose config --format json | jq -e '
  (.services.nginx.ports == [
    {"mode":"ingress","target":80,"published":"80","protocol":"tcp"}
  ]) and
  ((.services.nginx.volumes | length) == 1) and
  (.services.nginx.volumes[0].source | endswith("/setup/nginx/conf")) and
  (.services.nginx.volumes[0].target == "/etc/nginx") and
  (.services.nginx.volumes[0].read_only == true)
'
```

Expected: `false` and exit 1 because the current service still publishes 443 and has five mounts targeting the old paths.

- [ ] **Step 2: Replace the Nginx ports and volumes in Compose**

Edit only the `nginx` service in `docker-compose.yml` so its relevant section is:

```yaml
  nginx:
    image: nginx:1.30.4-trixie
    ports:
      - "80:80"
    volumes:
      - ./setup/nginx/conf:/etc/nginx:ro
```

Leave `restart`, `environment`, `healthcheck`, `logging`, and `networks` unchanged. Remove the 443 publication and the `html`, `media`, `ssl`, and `static` mounts.

- [ ] **Step 3: Update the README to match the official default service**

Make these exact semantic changes in `README.md`:

- Remove the environment prerequisite for Nginx certificate and content files.
- Keep the normal `docker compose up -d nginx` startup command.
- Add this service-recreation command after the startup sequence:

```bash
docker compose up -d --no-deps --force-recreate --wait --wait-timeout 60 nginx
```

- Replace the Nginx verification commands with:

```bash
docker compose run --rm --no-deps nginx nginx -t
curl --fail --silent --show-error http://127.0.0.1/ | grep -F 'Welcome to nginx!'
```

- State that Nginx serves the official image welcome page over HTTP, has no HTTPS listener, and no longer depends on an application upstream.
- Change the Nginx mapping documentation to:

```text
setup/nginx/conf/ -> /etc/nginx (read-only)
```

- Explain that the local tree is an exact snapshot of `nginx:1.30.4-trixie` and must be refreshed when the image tag changes.
- Remove port 443 from the published-port summary.
- Change the Nginx service-version table entry to `80:80` only.

- [ ] **Step 4: Run the rendered-Compose assertion and configuration checks**

Run the exact `docker compose config --format json | jq -e ...` assertion from Step 1 again.

Expected: `true` and exit 0.

Then run:

```bash
docker compose config --quiet
docker compose run --rm --no-deps nginx nginx -t
git diff --check
```

Expected: all commands exit 0; Nginx reports `syntax is ok` and `test is successful`.

- [ ] **Step 5: Recreate only the Nginx service and wait for health**

Run:

```bash
docker compose up -d --no-deps --force-recreate --wait --wait-timeout 60 nginx
```

Expected: the Nginx container is recreated and becomes healthy. No other Compose service is recreated or started.

If the command fails, capture evidence before changing anything else:

```bash
docker compose ps nginx
docker compose logs --no-color --tail 100 nginx
```

- [ ] **Step 6: Verify the default HTTP site and published port**

Run:

```bash
docker compose ps nginx
curl --fail --silent --show-error http://127.0.0.1/ | grep -F 'Welcome to nginx!'
docker compose port nginx 80
docker compose port nginx 443
```

Expected:

- `docker compose ps nginx` reports `healthy`.
- The HTTP request prints a line containing `Welcome to nginx!` and exits 0.
- Port 80 resolves to `0.0.0.0:80` (and may additionally show an IPv6 host publication depending on Docker).
- The port 443 command reports that the port is not published and exits nonzero.

- [ ] **Step 7: Inspect logs and final repository state**

Run:

```bash
docker compose logs --no-color --tail 50 nginx
git diff --check
git status --short
```

Expected: no Nginx configuration errors; an informational read-only `default.conf` message is acceptable. Repository changes are limited to `docker-compose.yml` and `README.md`. The existing `setup/nginx/html`, `media`, `ssl`, and `static` directories remain present and unchanged.

- [ ] **Step 8: Commit the Compose and documentation change**

Run:

```bash
git add docker-compose.yml README.md
git diff --cached --check
git diff --cached --name-status
git commit -m "Serve the official Nginx default site"
```

Expected staged changes: only `docker-compose.yml` and `README.md`.

- [ ] **Step 9: Run final verification against the committed state**

Run:

```bash
docker compose config --quiet
docker compose run --rm --no-deps nginx nginx -t
curl --fail --silent --show-error http://127.0.0.1/ | grep -F 'Welcome to nginx!'
git diff --check
git status --short
```

Expected: all verification commands exit 0, the welcome-page check prints a matching line, and `git status --short` has no output.
