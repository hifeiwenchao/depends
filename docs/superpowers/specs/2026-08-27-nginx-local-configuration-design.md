# Nginx Local Configuration Design

## Context

The Compose stack starts `nginx:1.30.4-trixie` directly. It currently mounts only `setup/nginx/conf/` at `/etc/nginx/conf.d`, while separate mounts provide site content, media, certificates, and static assets below `/etc/nginx`. The tracked `upstream.conf` defines domain redirects, TLS, static routes, and a uWSGI upstream.

The replacement must use the official image configuration unchanged, keep the complete Nginx configuration visible and versioned locally, and remove all custom site behavior. The official welcome page remains inside the image at `/usr/share/nginx/html`.

## Goals

- Store a complete snapshot of the official `/etc/nginx` tree in the repository.
- Mount that snapshot read-only at `/etc/nginx` with one Compose volume.
- Remove `upstream.conf` and all domain, TLS, static alias, and uWSGI behavior.
- Publish HTTP on all host interfaces with the existing short port syntax.
- Recreate and verify the Nginx service after the repository change.

## Non-goals

- Do not create a Dockerfile or custom image.
- Do not provide HTTPS or publish port 443.
- Do not copy or mount the official welcome-page content into the repository.
- Do not delete `setup/nginx/html`, `media`, `ssl`, or `static`; they become unused local directories.
- Do not change other services.

## Local Configuration Layout

`setup/nginx/conf/` mirrors the configuration tree shipped by `nginx:1.30.4-trixie`:

```text
setup/nginx/conf/
|-- conf.d/
|   `-- default.conf
|-- fastcgi_params
|-- mime.types
|-- modules -> /usr/lib/nginx/modules
|-- nginx.conf
|-- scgi_params
`-- uwsgi_params
```

All regular files are copied byte-for-byte from the pinned image. The `modules` entry remains an absolute symbolic link so it resolves to the module directory supplied by the image at runtime.

## Compose Design

The Nginx service continues to use `image: nginx:1.30.4-trixie`. Its volumes are replaced with a single read-only bind mount:

```yaml
volumes:
  - ./setup/nginx/conf:/etc/nginx:ro
```

The service publishes only:

```yaml
ports:
  - "80:80"
```

This short syntax binds the host port on all interfaces. The restart policy, health check, logging, timezone, and network remain unchanged.

## Runtime Behavior

Requests flow from host port 80 to the official default server and then to `/usr/share/nginx/html` inside the image. With no other server blocks, the default server accepts any HTTP `Host` value and serves the official welcome page.

The official entrypoint attempts to add an IPv6 listener to an unmodified `default.conf`. With the configuration mounted read-only, its script detects that the file cannot be modified, logs an informational message, and continues successfully. Nginx then uses the checked-in official configuration as-is.

No process listens on container port 443. There are no domain redirects, certificate references, content aliases, or upstream connections.

## Documentation

The README is updated to describe the single configuration mount, HTTP-only port, official default site, and service recreation command. Existing implementation and design documents remain historical records; this document supersedes their Nginx layout where they differ.

## Verification

Verification covers structure, source fidelity, syntax, runtime behavior, and cleanup:

1. Before implementation, demonstrate that the repository still contains `upstream.conf`, incomplete `/etc/nginx` coverage, and port 443.
2. Confirm that every regular local configuration file matches the corresponding file from `nginx:1.30.4-trixie`, and that the `modules` link target is `/usr/lib/nginx/modules`.
3. Run `docker compose config --quiet` and inspect the rendered Nginx mounts and ports.
4. Mount the local tree into the official image and run `nginx -t`.
5. Run `docker compose up -d --force-recreate nginx` and wait for the service to become healthy.
6. Request `http://127.0.0.1/` and confirm an HTTP 200 response containing `Welcome to nginx!`.
7. Confirm that only port 80 is published and no task-created temporary containers remain.
8. Run `git diff --check` and inspect the final worktree changes.

If configuration validation fails, the running service is not recreated. If recreation succeeds but the health or HTTP check fails, container status and logs are captured before reporting the failure.

## Upgrade Rule

When the Nginx image tag changes, refresh the entire local configuration snapshot from that exact image in the same change. This prevents the checked-in configuration from drifting away from the runtime image version.
