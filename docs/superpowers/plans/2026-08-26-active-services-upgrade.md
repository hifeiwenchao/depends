# Active Services Upgrade Implementation Plan

> **Current status:** The detailed Tasks 1–7 below are preserved as implementation history and are superseded by this six-service plan plus the Task 8–10 reports. Do not execute their stale four-service commands or three-directory deletion examples.

## Current Six-Service Plan

**Goal:** Maintain six active services at exact versions: Nginx 1.30.4, MySQL 9.7.2, Redis 8.10.1, MongoDB 8.3.8, RabbitMQ 4.3.5 Management, and Elasticsearch 9.5.2.

**Current task map:** Tasks 1–7 upgraded the original four services and documentation; Task 8 added RabbitMQ with Management and container-internal Prometheus; Task 9 added single-node Elasticsearch with HTTP on host loopback and transport bound to container loopback; Task 10 applies final security, privilege, healthcheck, reset-documentation, restoration, and review corrections. The canonical execution evidence is in `.superpowers/sdd/2026-08-26-active-services-upgrade/task-1-report.md` through `task-10-report.md`.

**Current operational contract:** Use one Compose stack, blank password values in `.env.example`, ignored local `.env`, loopback-only host publications, bounded shared logging for all six services, authenticated healthchecks, Redis ACL generation in tmpfs followed by the Docker Official Redis entrypoint, and exact initialization-only credential semantics documented in README.

**Current reset boundary:** Only `setup/mysql/data/`, `setup/redis/data/`, `setup/mongo/db/`, `setup/rabbitmq/data/`, and `setup/elasticsearch/data/` are reset targets. Follow the executable README procedure: stop exactly those five services, verify exact canonical containment, display paths, obtain exact confirmation, recheck, preserve parents and `.gitkeep`, and never use broad deletion or `docker compose down -v`.

**Current checks:** Run Python static/README/spec contracts, `sh -n` on shell wrappers and extracted README shell, Python syntax validation for the embedded reset program, Compose config with non-secret placeholders, rendered six-service assertions, and `git diff --check`. Docker-backed checks are required before making fresh runtime claims, but must not run when the active instruction forbids Docker.

**Spec:** `docs/superpowers/specs/2026-08-26-active-services-upgrade-design.md`

## Superseded Historical Tasks

> **Historical instruction:** The original agent workflow and task steps follow unchanged to preserve review history. Where they conflict with the current six-service plan above, the current plan, design spec, README, and later task reports govern.

## Global Constraints

- Upgrade only active Nginx, MySQL, Redis, and MongoDB services.
- Use exact tags `nginx:1.30.4-trixie`, `mysql:9.7.2`, `redis:8.10.1`, and `mongo:8.3.8-noble`.
- Do not preserve or migrate existing MySQL, Redis, or MongoDB data.
- Do not delete runtime data until the user explicitly confirms the exact three target directories at execution time.
- Delete only contents of `setup/mysql/data/`, `setup/redis/data/`, and `setup/mongo/db/`; preserve parent directories and all configuration/log paths.
- Do not execute `docker compose down -v`.
- Bind host ports only to `127.0.0.1`.
- Do not commit real credentials, generated ACL files, or runtime data.
- Do not create a default MySQL application database.
- Preserve unrelated working-tree changes and visible `.DS_Store` files.
- If Docker daemon access is unavailable, complete static checks and report runtime checks as pending.

---

## File Map

- Create `.env.example`: variable contract without real values.
- Modify `.gitignore`: ignore local environments and macOS metadata while retaining `.env.example`.
- Modify `docker-compose.yml`: exact versions, loopback ports, environment contract, health checks, logging reuse, restart policy, Redis startup wrapper, and removal of obsolete Compose syntax.
- Modify `setup/nginx/Dockerfile`: exact modern base image.
- Modify `setup/nginx/conf/upstream.conf`: syntax fix and correct uWSGI parameters.
- Modify `setup/mysql/conf/my.cnf`: remove authentication option deleted by MySQL 9.x.
- Replace `setup/redis/conf/redis.conf`: focused Redis 8 configuration without credentials.
- Create `setup/redis/docker-entrypoint.sh`: generate a tmpfs ACL and launch Redis.
- Modify `README.md`: setup, startup, verification, and destructive reset instructions.
- Preserve `setup/mysql/data/`, `setup/redis/data/`, and `setup/mongo/db/` as runtime directories; clear only their contents after explicit confirmation.

### Task 1: Environment and Compose policy

**Files:**
- Create: `.env.example`
- Modify: `.gitignore`
- Modify: `docker-compose.yml`

**Interfaces:**
- Consumes: Environment variables listed in `.env.example`.
- Produces: A Compose contract used by all later component tasks, including exact service names, loopback ports, health checks, `/run/redis` tmpfs, and Redis ACL environment variables.

- [ ] **Step 1: Write a failing static contract check**

Run this read-only assertion before changing files:

```bash
python3 - <<'PY'
from pathlib import Path
compose = Path('docker-compose.yml').read_text()
ignore = Path('.gitignore').read_text()
assert not compose.startswith('version:')
for image in (
    'nginx:1.30.4-trixie',
    'mysql:9.7.2',
    'redis:8.10.1',
    'mongo:8.3.8-noble',
):
    assert image in compose
for port in (
    '127.0.0.1:80:80',
    '127.0.0.1:443:443',
    '127.0.0.1:3306:3306',
    '127.0.0.1:6379:6379',
    '127.0.0.1:27017:27017',
):
    assert port in compose
assert '.env.example' in Path('.').glob('*')
assert '.env' in ignore and '!.env.example' in ignore
assert '123456' not in compose
PY
```

Expected: FAIL because the new contract is not yet present.

- [ ] **Step 2: Add `.env.example`**

Create exactly:

```dotenv
MYSQL_ROOT_PASSWORD=
MYSQL_USER=dev
MYSQL_PASSWORD=
REDIS_USERNAME=default
REDIS_PASSWORD=
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=
TZ=Asia/Shanghai
```

- [ ] **Step 3: Extend `.gitignore`**

Add:

```gitignore
.DS_Store
**/.DS_Store
.env
.env.*
!.env.example
```

Do not delete the existing untracked `.DS_Store` files.

- [ ] **Step 4: Refactor the Compose common structure**

At the top of `docker-compose.yml`, remove `version: "3"` and add:

```yaml
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "100m"
    max-file: "3"
```

For all active services:

```yaml
restart: unless-stopped
logging: *default-logging
networks:
  - main
```

Remove redundant `expose` entries and explicit aliases. Preserve the existing `main` network declaration.

- [ ] **Step 5: Update exact images, ports, and environment declarations**

Use these exact image/base contracts:

```yaml
mysql:
  image: mysql:9.7.2

redis:
  image: redis:8.10.1

mongo:
  image: mongo:8.3.8-noble
```

Use loopback port mappings:

```yaml
nginx:
  ports:
    - "127.0.0.1:80:80"
    - "127.0.0.1:443:443"

mysql:
  ports:
    - "127.0.0.1:3306:3306"

redis:
  ports:
    - "127.0.0.1:6379:6379"

mongo:
  ports:
    - "127.0.0.1:27017:27017"
```

Replace active credential literals with mapping-form environment values:

```yaml
mysql:
  environment:
    MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}
    MYSQL_USER: ${MYSQL_USER:-dev}
    MYSQL_PASSWORD: ${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}
    TZ: ${TZ:-Asia/Shanghai}

redis:
  environment:
    REDIS_USERNAME: ${REDIS_USERNAME:-default}
    REDIS_PASSWORD: ${REDIS_PASSWORD:?REDIS_PASSWORD is required}
    TZ: ${TZ:-Asia/Shanghai}
  tmpfs:
    - /run/redis:mode=700

mongo:
  environment:
    MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME:-admin}
    MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD:?MONGO_INITDB_ROOT_PASSWORD is required}
    TZ: ${TZ:-Asia/Shanghai}
```

Do not add `MYSQL_DATABASE`.

- [ ] **Step 6: Add health checks**

Use exec-form checks. Escape `$` as `$$` where Compose must pass a container variable:

```yaml
nginx:
  healthcheck:
    test: ["CMD", "nginx", "-t"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 10s

mysql:
  healthcheck:
    test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -uroot -p\"$$MYSQL_ROOT_PASSWORD\" --silent"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 30s

redis:
  healthcheck:
    test: ["CMD-SHELL", "redis-cli --user \"$$REDIS_USERNAME\" --pass \"$$REDIS_PASSWORD\" --no-auth-warning ping | grep -qx PONG"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 10s

mongo:
  healthcheck:
    test: ["CMD-SHELL", "mongosh --quiet --host 127.0.0.1 --username \"$$MONGO_INITDB_ROOT_USERNAME\" --password \"$$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval 'quit(db.adminCommand({ping:1}).ok ? 0 : 2)'"]
    interval: 10s
    timeout: 10s
    retries: 10
    start_period: 30s
```

- [ ] **Step 7: Run the static contract check with temporary values**

```bash
MYSQL_ROOT_PASSWORD=test-root \
MYSQL_PASSWORD=test-dev \
REDIS_PASSWORD=test-redis \
MONGO_INITDB_ROOT_PASSWORD=test-mongo \
docker compose config --quiet

python3 - <<'PY'
from pathlib import Path
compose = Path('docker-compose.yml').read_text()
assert not compose.startswith('version:')
for image in ('mysql:9.7.2', 'redis:8.10.1', 'mongo:8.3.8-noble'):
    assert image in compose
for port in ('127.0.0.1:80:80', '127.0.0.1:443:443', '127.0.0.1:3306:3306', '127.0.0.1:6379:6379', '127.0.0.1:27017:27017'):
    assert port in compose
assert '123456' not in compose
assert Path('.env.example').exists()
PY

git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 8: Review the diff and commit if the user requested commits**

```bash
git diff -- .env.example .gitignore docker-compose.yml
```

If authorized to commit:

```bash
git add .env.example .gitignore docker-compose.yml
git commit -m "chore: define upgraded service runtime policy

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 2: Nginx 1.30.4 upgrade

**Files:**
- Modify: `setup/nginx/Dockerfile`
- Modify: `setup/nginx/conf/upstream.conf`
- Modify: `docker-compose.yml` only if Task 1 did not add the Nginx health check.

**Interfaces:**
- Consumes: Compose `nginx` service and `main` network from Task 1.
- Produces: `depends-nginx` built from `nginx:1.30.4-trixie` with a syntactically valid uWSGI configuration.

- [ ] **Step 1: Record the expected failure before editing**

```bash
python3 - <<'PY'
from pathlib import Path
dockerfile = Path('setup/nginx/Dockerfile').read_text()
conf = Path('setup/nginx/conf/upstream.conf').read_text()
assert 'FROM nginx:1.30.4-trixie' in dockerfile
assert 'server_name                    feiwenchao.com;' in conf
assert 'proxy_set_header X-Real-IP' not in conf
assert 'uwsgi_param HTTP_X_REAL_IP $remote_addr;' in conf
PY
```

Expected: FAIL on the old image and missing semicolon.

- [ ] **Step 2: Pin the Nginx base**

Change the Dockerfile first line to:

```dockerfile
FROM nginx:1.30.4-trixie
```

Do not change unrelated content-copy behavior in this task.

- [ ] **Step 3: Fix the Nginx server and uWSGI configuration**

Make these exact semantic changes:

```nginx
server_name                    feiwenchao.com;
```

Delete the commented `ssl off` line. Replace the ineffective proxy directives in `location /` with:

```nginx
uwsgi_param HTTP_HOST $http_host;
uwsgi_param HTTP_X_REAL_IP $remote_addr;
uwsgi_param HTTP_X_FORWARDED_PROTO $scheme;
uwsgi_pass blog_stream;
include /etc/nginx/uwsgi_params;
```

Remove `proxy_pass_header Server`, `proxy_set_header`, and `proxy_redirect` from that uWSGI location.

- [ ] **Step 4: Re-run static assertions**

```bash
python3 - <<'PY'
from pathlib import Path
dockerfile = Path('setup/nginx/Dockerfile').read_text()
conf = Path('setup/nginx/conf/upstream.conf').read_text()
assert 'FROM nginx:1.30.4-trixie' in dockerfile
assert 'server_name                    feiwenchao.com;' in conf
assert 'proxy_set_header X-Real-IP' not in conf
assert 'uwsgi_param HTTP_X_REAL_IP $remote_addr;' in conf
assert 'uwsgi_param HTTP_X_FORWARDED_PROTO $scheme;' in conf
PY

git diff --check
```

Expected: exit 0.

- [ ] **Step 5: Run Docker-backed Nginx validation when daemon access exists**

```bash
docker compose build --pull nginx
docker compose run --rm nginx nginx -V
docker compose run --rm nginx nginx -t
docker compose run --rm nginx nginx -T >/tmp/depends-nginx-expanded.conf
```

Expected: build succeeds; `nginx -t` reports syntax successful and test successful. If Docker is unavailable, record these checks as pending instead of passing.

- [ ] **Step 6: Start and smoke-test Nginx**

```bash
docker compose up -d nginx
docker compose ps nginx
curl -I http://127.0.0.1/
curl -Ik https://127.0.0.1/ -H 'Host: feiwenchao.com'
```

Expected: service becomes healthy; HTTP redirects to HTTPS; HTTPS reaches Nginx. `-k` tests transport only and does not validate the repository certificate.

- [ ] **Step 7: Commit if authorized**

```bash
git add setup/nginx/Dockerfile setup/nginx/conf/upstream.conf
git commit -m "chore: upgrade nginx to 1.30.4

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 3: Redis 8.10 configuration and ACL startup

**Files:**
- Replace: `setup/redis/conf/redis.conf`
- Create: `setup/redis/docker-entrypoint.sh`
- Modify: `docker-compose.yml` Redis command/volumes from Task 1.

**Interfaces:**
- Consumes: `REDIS_USERNAME`, `REDIS_PASSWORD`, `/run/redis` tmpfs, and `setup/redis/data:/data` from Task 1.
- Produces: `/run/redis/users.acl` at container startup and a Redis server launched with `/etc/redis/redis.conf`.

- [ ] **Step 1: Write a failing configuration contract check**

```bash
python3 - <<'PY'
from pathlib import Path
conf = Path('setup/redis/conf/redis.conf').read_text()
entry = Path('setup/redis/docker-entrypoint.sh')
assert len(conf.splitlines()) < 80
assert 'protected-mode yes' in conf
assert 'aclfile /run/redis/users.acl' in conf
assert 'appendfsync everysec' in conf
assert 'aof-use-rdb-preamble yes' in conf
assert 'requirepass ' not in conf
assert entry.exists()
PY
```

Expected: FAIL because the old full configuration and plaintext password remain.

- [ ] **Step 2: Replace Redis configuration with a minimal Redis 8 configuration**

Use:

```conf
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
supervised no
daemonize no
loglevel notice
logfile ""
databases 16
aclfile /run/redis/users.acl

dir /data
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes

appendonly yes
appenddirname appendonlydir
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

replica-serve-stale-data yes
replica-read-only yes
hash-max-listpack-entries 512
hash-max-listpack-value 64
list-max-listpack-size -2
zset-max-listpack-entries 128
zset-max-listpack-value 64
```

No password or username literal belongs in this file.

- [ ] **Step 3: Create the ACL-generating startup wrapper**

Create `setup/redis/docker-entrypoint.sh`:

```sh
#!/bin/sh
set -eu

: "${REDIS_USERNAME:?REDIS_USERNAME is required}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"

case "$REDIS_USERNAME$REDIS_PASSWORD" in
  *'\n'*|*'\r'*)
    echo "Redis credentials must not contain line breaks" >&2
    exit 64
    ;;
esac

mkdir -p /run/redis
umask 077
printf 'user %s on >%s ~* &* +@all\n' "$REDIS_USERNAME" "$REDIS_PASSWORD" > /run/redis/users.acl

exec redis-server /etc/redis/redis.conf
```

Mark it executable:

```bash
chmod 0755 setup/redis/docker-entrypoint.sh
```

During implementation, verify Redis ACL token escaping against Redis 8.10.1. If usernames/passwords containing spaces, `#`, `>`, `<`, `~`, `&`, or ACL operators cannot be represented safely with this direct format, constrain `.env.example` and README to URL-safe generated credentials and add a wrapper validation character class before runtime use.

- [ ] **Step 4: Wire the Redis wrapper into Compose**

Use read-only mounts and explicit entrypoint:

```yaml
redis:
  volumes:
    - ./setup/redis/conf/redis.conf:/etc/redis/redis.conf:ro
    - ./setup/redis/docker-entrypoint.sh:/usr/local/bin/depends-redis-entrypoint:ro
    - ./setup/redis/data:/data
  entrypoint: ["/usr/local/bin/depends-redis-entrypoint"]
```

Remove the old `command: redis-server /etc/redis/redis.conf`.

- [ ] **Step 5: Run static checks**

```bash
python3 - <<'PY'
from pathlib import Path
conf = Path('setup/redis/conf/redis.conf').read_text()
entry = Path('setup/redis/docker-entrypoint.sh')
assert len(conf.splitlines()) < 80
for setting in ('protected-mode yes', 'aclfile /run/redis/users.acl', 'appendfsync everysec', 'aof-use-rdb-preamble yes', 'stop-writes-on-bgsave-error yes'):
    assert setting in conf
assert 'requirepass ' not in conf
assert entry.stat().st_mode & 0o111
PY

sh -n setup/redis/docker-entrypoint.sh
MYSQL_ROOT_PASSWORD=test-root MYSQL_PASSWORD=test-dev REDIS_PASSWORD=test-redis MONGO_INITDB_ROOT_PASSWORD=test-mongo docker compose config --quiet
git diff --check
```

Expected: exit 0.

- [ ] **Step 6: Run a container parser/start test when Docker is available**

```bash
docker run --rm \
  -e REDIS_USERNAME=default \
  -e REDIS_PASSWORD=test-redis \
  -v "$PWD/setup/redis/conf/redis.conf:/etc/redis/redis.conf:ro" \
  -v "$PWD/setup/redis/docker-entrypoint.sh:/usr/local/bin/depends-redis-entrypoint:ro" \
  --tmpfs /run/redis:mode=700 \
  --entrypoint /usr/local/bin/depends-redis-entrypoint \
  redis:8.10.1 \
  --version
```

If this entrypoint shape starts the server instead of honoring `--version`, use a bounded `docker run -d`, wait for PING, then remove the container. Expected: Redis parses the configuration and accepts authenticated PING.

- [ ] **Step 7: Commit if authorized**

```bash
git add setup/redis/conf/redis.conf setup/redis/docker-entrypoint.sh docker-compose.yml
git commit -m "chore: upgrade redis configuration to 8.10

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 4: MySQL 9.7 configuration

**Files:**
- Modify: `setup/mysql/conf/my.cnf`
- Modify: `docker-compose.yml` only if Task 1 did not complete the MySQL service.

**Interfaces:**
- Consumes: `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD`, and the existing `setup/mysql/data:/var/lib/mysql` mount.
- Produces: MySQL 9.7-compatible server configuration using default `caching_sha2_password`.

- [ ] **Step 1: Write a failing compatibility check**

```bash
python3 - <<'PY'
from pathlib import Path
conf = Path('setup/mysql/conf/my.cnf').read_text()
compose = Path('docker-compose.yml').read_text()
assert 'default_authentication_plugin' not in conf
assert 'mysql:9.7.2' in compose
assert 'MYSQL_DATABASE' not in compose
PY
```

Expected: FAIL because the removed authentication option remains.

- [ ] **Step 2: Remove the obsolete authentication option**

Resulting `setup/mysql/conf/my.cnf`:

```ini
[mysqld]
bind-address = 0.0.0.0
skip-name-resolve
```

Do not add a replacement authentication line.

- [ ] **Step 3: Run static checks**

```bash
python3 - <<'PY'
from pathlib import Path
conf = Path('setup/mysql/conf/my.cnf').read_text()
compose = Path('docker-compose.yml').read_text()
assert 'default_authentication_plugin' not in conf
assert 'mysql_native_password' not in conf
assert 'mysql:9.7.2' in compose
assert 'MYSQL_DATABASE' not in compose
PY

git diff --check
```

Expected: exit 0.

- [ ] **Step 4: Validate MySQL config when Docker is available**

```bash
docker pull mysql:9.7.2
docker run --rm \
  -v "$PWD/setup/mysql/conf/my.cnf:/etc/my.cnf:ro" \
  mysql:9.7.2 \
  mysqld --validate-config
```

Expected: exit 0. If this exact image does not expose `--validate-config`, run the service against an empty temporary Docker volume and inspect startup logs instead; do not point it at `setup/mysql/data` before deletion confirmation.

- [ ] **Step 5: Commit if authorized**

```bash
git add setup/mysql/conf/my.cnf docker-compose.yml
git commit -m "chore: update mysql configuration for 9.7

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 5: Destructive data reset gate

**Files:**
- Delete contents only: `setup/mysql/data/`
- Delete contents only: `setup/redis/data/`
- Delete contents only: `setup/mongo/db/`

**Interfaces:**
- Consumes: User confirmation naming these exact resolved directories.
- Produces: Three empty parent directories ready for fresh initialization.

- [ ] **Step 1: Stop only the stateful services**

```bash
docker compose stop mysql redis mongo
```

Expected: services stopped. If Docker is unavailable, stop and leave this entire task pending.

- [ ] **Step 2: Resolve and display exact deletion targets**

```bash
python3 - <<'PY'
from pathlib import Path
root = Path.cwd().resolve()
expected = [
    root / 'setup/mysql/data',
    root / 'setup/redis/data',
    root / 'setup/mongo/db',
]
for path in expected:
    resolved = path.resolve()
    assert resolved == path
    assert resolved.parent.parent == root / 'setup' / path.parent.name
    print(resolved)
PY
```

Expected: exactly the three approved repository paths, one per line.

- [ ] **Step 3: Ask the user for explicit irreversible-action confirmation**

Quote the three resolved paths and state that all files, including hidden files, will be permanently deleted. Do not infer approval from the earlier architectural choice; obtain a fresh confirmation immediately before deletion.

- [ ] **Step 4: Delete only directory contents after confirmation**

Use Python to avoid glob/hidden-file errors and to re-check containment:

```bash
python3 - <<'PY'
from pathlib import Path
import shutil

root = Path.cwd().resolve()
targets = (
    root / 'setup/mysql/data',
    root / 'setup/redis/data',
    root / 'setup/mongo/db',
)
for target in targets:
    target = target.resolve()
    assert target.parent.parent.parent == root
    for child in target.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()
    assert target.is_dir()
    assert not any(target.iterdir())
    print(f'cleared {target}')
PY
```

Expected: three `cleared` lines; parent directories still exist and are empty.

- [ ] **Step 5: Verify no unrelated path changed due to deletion**

```bash
git status --short
git diff --check
```

Expected: only planned tracked configuration/documentation changes plus pre-existing unrelated changes. Runtime data was ignored and should not appear as tracked deletions.

### Task 6: Stateful runtime initialization and verification

**Files:**
- Runtime only: `setup/redis/data/`, `setup/mongo/db/`, `setup/mysql/data/`
- No source edits unless validation uncovers a specific defect; any such defect starts a new red/green cycle in the owning task.

**Interfaces:**
- Consumes: Empty directories from Task 5 and a local `.env` populated from `.env.example`.
- Produces: Healthy Redis 8.10.1, MongoDB 8.3.8, and MySQL 9.7.2 development services.

- [ ] **Step 1: Create local environment without printing secrets**

```bash
cp .env.example .env
```

Ask the user to edit `.env` locally with strong development credentials. In Claude Code they can use an interactive editor or type a shell command prefixed with `!`; do not request they paste credentials into chat.

Check only presence/non-empty values without printing them:

```bash
python3 - <<'PY'
from pathlib import Path
required = {
    'MYSQL_ROOT_PASSWORD',
    'MYSQL_PASSWORD',
    'REDIS_PASSWORD',
    'MONGO_INITDB_ROOT_PASSWORD',
}
values = {}
for raw in Path('.env').read_text().splitlines():
    if raw and not raw.lstrip().startswith('#') and '=' in raw:
        key, value = raw.split('=', 1)
        values[key] = value
missing = sorted(k for k in required if not values.get(k))
assert not missing, 'missing required values: ' + ', '.join(missing)
print('required environment values are present')
PY
```

- [ ] **Step 2: Initialize and verify Redis**

```bash
docker compose up -d redis
docker compose ps redis
docker compose logs --tail=200 redis
docker compose exec redis redis-cli \
  --user "$REDIS_USERNAME" \
  --pass "$REDIS_PASSWORD" \
  --no-auth-warning PING
docker compose exec redis redis-cli \
  --user "$REDIS_USERNAME" \
  --pass "$REDIS_PASSWORD" \
  --no-auth-warning INFO server
docker compose exec redis redis-cli \
  --user "$REDIS_USERNAME" \
  --pass "$REDIS_PASSWORD" \
  --no-auth-warning CONFIG GET appendonly appendfsync aof-use-rdb-preamble protected-mode
docker compose exec redis redis-cli \
  --user "$REDIS_USERNAME" \
  --pass "$REDIS_PASSWORD" \
  --no-auth-warning ACL LIST
```

Expected: healthy; PONG; version 8.10.1; AOF yes; appendfsync everysec; protected mode yes; configured ACL user enabled.

If variables are only in `.env` and not exported to the host shell, source them without printing (`set -a; . ./.env; set +a`) in the same shell before client commands.

- [ ] **Step 3: Initialize and verify MongoDB**

```bash
docker compose up -d mongo
docker compose ps mongo
docker compose logs --tail=200 mongo
set -a; . ./.env; set +a
docker compose exec mongo mongosh --quiet \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval 'printjson({version: db.version(), ping: db.adminCommand({ping:1}), fcv: db.adminCommand({getParameter:1, featureCompatibilityVersion:1})})'
```

Expected: healthy; version 8.3.8; ping `ok: 1`; FCV reported. If logs show WiredTiger/shared-filesystem incompatibility, stop MongoDB and open a separate approved change to replace `setup/mongo/db:/data/db` with a named volume.

- [ ] **Step 4: Initialize and verify MySQL**

```bash
docker compose up -d mysql
docker compose ps mysql
docker compose logs --tail=200 mysql
set -a; . ./.env; set +a
docker compose exec mysql mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping
docker compose exec mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT VERSION(), @@version_comment;
SELECT user, host, plugin FROM mysql.user;
SHOW VARIABLES LIKE 'default_authentication_plugin';
SHOW DATABASES;
"
```

Expected: healthy; version 9.7.2; initialized users use `caching_sha2_password`; `default_authentication_plugin` query returns no row; only system schemas exist because no `MYSQL_DATABASE` was set.

- [ ] **Step 5: Verify loopback-only host access and overall health**

```bash
docker compose ps
python3 - <<'PY'
import json, subprocess
raw = subprocess.check_output(['docker', 'compose', 'config', '--format', 'json'])
config = json.loads(raw)
expected = {
    ('nginx', 80), ('nginx', 443), ('mysql', 3306), ('redis', 6379), ('mongo', 27017),
}
seen = set()
for service, cfg in config['services'].items():
    for port in cfg.get('ports', []):
        published = int(port['published'])
        assert port.get('host_ip') == '127.0.0.1', (service, port)
        seen.add((service, published))
assert seen == expected, seen
print('all published ports are loopback-only')
PY
```

Expected: all active services healthy and exactly five loopback-only published ports.

### Task 7: Operator documentation and final verification

**Files:**
- Modify: `README.md`
- Verify: all modified files from Tasks 1–6.

**Interfaces:**
- Consumes: Final Compose/environment/runtime behavior.
- Produces: A reproducible personal-development setup guide and evidence-backed completion report.

- [ ] **Step 1: Write a failing README contract check**

```bash
python3 - <<'PY'
from pathlib import Path
readme = Path('README.md').read_text()
for heading in ('## Requirements', '## Configure', '## Start', '## Validate', '## Reset data', '## Service versions'):
    assert heading in readme
for version in ('1.30.4', '9.7.2', '8.10.1', '8.3.8'):
    assert version in readme
PY
```

Expected: FAIL because README currently contains only its title.

- [ ] **Step 2: Document prerequisites and configuration**

README must state:

- This stack is for a personal development machine, not production.
- Docker Engine/Desktop and Compose v2 are required.
- Copy `.env.example` to `.env` and fill required values locally.
- Never commit `.env` or paste credentials into issue/chat logs.
- No MySQL application database is created automatically.

- [ ] **Step 3: Document startup and validation**

Include exact commands:

```bash
docker compose config --quiet
docker compose build nginx
docker compose up -d redis
docker compose up -d mongo
docker compose up -d mysql
docker compose up -d nginx
docker compose ps
```

List service versions and loopback endpoints. Explain that all services must become healthy.

- [ ] **Step 4: Document destructive reset**

Document that reset permanently deletes only contents beneath:

```text
setup/mysql/data/
setup/redis/data/
setup/mongo/db/
```

Require stopping services first. Warn against `docker compose down -v` and against running MongoDB 8.3 on old MongoDB 5 files. Document the macOS named-volume fallback if WiredTiger rejects the bind mount.

- [ ] **Step 5: Run README contract and repository checks**

```bash
python3 - <<'PY'
from pathlib import Path
readme = Path('README.md').read_text()
for heading in ('## Requirements', '## Configure', '## Start', '## Validate', '## Reset data', '## Service versions'):
    assert heading in readme
for version in ('1.30.4', '9.7.2', '8.10.1', '8.3.8'):
    assert version in readme
PY

MYSQL_ROOT_PASSWORD=test-root MYSQL_PASSWORD=test-dev REDIS_PASSWORD=test-redis MONGO_INITDB_ROOT_PASSWORD=test-mongo docker compose config --quiet
git diff --check
git status --short
```

Expected: assertions and static checks pass; status contains only planned edits plus explicitly acknowledged pre-existing files.

- [ ] **Step 6: Run the full runtime verification if Docker is available**

Repeat Task 6 checks and additionally:

```bash
docker compose run --rm nginx nginx -t
curl -I http://127.0.0.1/
curl -Ik https://127.0.0.1/ -H 'Host: feiwenchao.com'
```

Expected: all four services healthy; component versions match; authenticated checks pass; Nginx syntax passes. If Docker remains unavailable, state that runtime verification was skipped and do not claim the stack is operational.

- [ ] **Step 7: Review for accidental secret and data inclusion**

```bash
git diff -- . ':!docs/superpowers/specs/2026-08-26-active-services-upgrade-design.md' ':!docs/superpowers/plans/2026-08-26-active-services-upgrade.md'
git status --short
```

Verify manually:

- No `.env` is staged.
- No value from the local `.env` appears in tracked diffs.
- No runtime database file is staged.
- Unrelated `.DS_Store` files remain untouched.
- No unrequested commit or push occurred.

- [ ] **Step 8: Commit final documentation if authorized**

```bash
git add README.md docs/superpowers/specs/2026-08-26-active-services-upgrade-design.md docs/superpowers/plans/2026-08-26-active-services-upgrade.md
git commit -m "docs: document active service upgrade workflow

Co-Authored-By: Claude <noreply@anthropic.com>"
```

Do not commit unless explicitly requested.
