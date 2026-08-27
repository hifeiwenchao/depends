# depends

Personal-development service stack for a single machine. This setup is **not for production**. It binds service ports to loopback and assumes that the operator controls the local Docker host.

## Requirements

- Docker Engine or Docker Desktop.
- Docker Compose v2 (`docker compose`, not the legacy `docker-compose` command).
- A local copy of the repository with the Nginx certificate files and content expected by this stack.
- For Elasticsearch on Docker Desktop, share the repository path, allocate at least 4 GiB to the Docker Desktop Linux VM, and ensure `vm.max_map_count` is at least `1048576` inside that VM before startup.

## Configure

Copy the example environment file and fill in the required values locally:

```bash
cp .env.example .env
```

Set the required local credentials in `.env`: `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `REDIS_PASSWORD`, `MONGO_INITDB_ROOT_PASSWORD`, `RABBITMQ_DEFAULT_PASS`, and `ELASTIC_PASSWORD`. Generate every password from the URL-safe character set `[A-Za-z0-9._~-]+`; the validation examples source `.env` as POSIX shell, and Redis ACL generation enforces this same set. `RABBITMQ_DEFAULT_USER` defaults to `dev`; do not use `guest` for normal container-network clients. Keep `.env` local: never commit it, and never paste credentials into issue or chat logs. Do not expose or share its contents.

The Compose file does **not** create a MySQL application database automatically. Create an application database explicitly after MySQL is healthy if your application requires one.

MySQL applies `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, and `MYSQL_PASSWORD` only while initializing an empty `setup/mysql/data/`. Changing those values in `.env` does not rotate accounts in an initialized data directory; use authenticated `ALTER USER` statements for rotation. MongoDB likewise applies `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` only while initializing an empty `setup/mongo/db/`; changing `.env` later does not rotate that persisted user, so rotate it with an authenticated MongoDB user-management command.

On its first start with an empty data directory, RabbitMQ creates the configured user and uses the default `/` vhost; it does not create an application-specific vhost. The RabbitMQ bootstrap environment variables apply only during initialization, so changing them later does not rotate credentials stored in persisted broker data. Elasticsearch similarly applies `ELASTIC_PASSWORD` only when initializing empty data. For an initialized cluster, changing the environment does not rotate the built-in `elastic` password; use `elasticsearch-reset-password` instead.

## Start

Validate the rendered Compose configuration, build Nginx, then start the services in dependency-safe order:

```bash
docker compose config --quiet
docker compose build nginx
docker compose up -d redis
docker compose up -d mongo
docker compose up -d mysql
docker compose up -d nginx
docker compose up -d rabbitmq
docker compose up -d elasticsearch
docker compose ps
```

Start and validate stateful services one at a time in that order; wait for each service to become healthy before proceeding. The Nginx build uses `nginx:1.30.4-trixie`. The other services use the exact versions listed below. All six services should be running and should eventually report `healthy`.

## Validate

Inspect service state and wait for every service health check to pass:

```bash
docker compose ps
docker compose run --rm nginx nginx -t
curl -I http://127.0.0.1/
curl -Ik https://127.0.0.1/ -H 'Host: feiwenchao.me'
```

The HTTP request may return a redirect to HTTPS. The HTTPS root request depends on the configured external uWSGI upstream and may time out when that upstream is unavailable; this does not by itself show that Nginx failed to accept HTTPS. Use a known local static path to distinguish Nginx transport/configuration from upstream availability. Do not disable certificate verification beyond the local `-k` smoke-test option. Confirm the exact loopback bindings are `127.0.0.1:80`, `127.0.0.1:443`, `127.0.0.1:3306`, `127.0.0.1:6379`, `127.0.0.1:27017`, `127.0.0.1:5672`, `127.0.0.1:15672`, and `127.0.0.1:9200`. RabbitMQ's Prometheus port `15692` remains container-internal, and Elasticsearch transport port `9300` must not be published to the host.

For component checks, use authenticated commands without putting passwords in shell history or logs. Examples:

```bash
# Export .env only in this shell. Disable tracing first so values are not echoed.
set +x
set -a
. ./.env
set +a
docker compose exec -e REDISCLI_AUTH="$REDIS_PASSWORD" redis redis-cli --user "$REDIS_USERNAME" --no-auth-warning ping
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" docker compose exec -e MYSQL_PWD mysql mysql -h 127.0.0.1 -uroot --silent --skip-column-names --execute='SELECT 1'
docker compose exec mongo mongosh --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval 'quit(db.adminCommand({ping:1}).ok ? 0 : 2)'
docker compose exec rabbitmq rabbitmq-diagnostics -q ping
curl --fail --silent --show-error --user "$RABBITMQ_DEFAULT_USER:$RABBITMQ_DEFAULT_PASS" http://127.0.0.1:15672/api/overview >/dev/null
curl --fail --silent --show-error --user "elastic:$ELASTIC_PASSWORD" 'http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=5s' >/dev/null
unset REDIS_PASSWORD MYSQL_ROOT_PASSWORD MYSQL_PASSWORD MONGO_INITDB_ROOT_PASSWORD RABBITMQ_DEFAULT_PASS ELASTIC_PASSWORD
```

Redis should answer `PONG`; MySQL should report that it is alive; MongoDB should answer a ping command successfully. RabbitMQ should pass broker diagnostics and expose its authenticated Management API only at `127.0.0.1:15672`. Elasticsearch should require the `elastic` password over plaintext HTTP at loopback-only `http://127.0.0.1:9200` and reach yellow or green single-node cluster health. Password-over-HTTP is deliberate only because the endpoint is loopback-bound; it is not appropriate for LAN or production exposure. Verify the reported component versions are the versions below and that all six Compose services are healthy before using the stack.

RabbitMQ uses these local mappings:

```text
setup/rabbitmq/conf/rabbitmq.conf -> /etc/rabbitmq/rabbitmq.conf (read-only)
setup/rabbitmq/conf/enabled_plugins -> /etc/rabbitmq/enabled_plugins (read-only)
setup/rabbitmq/data/ -> /var/lib/rabbitmq
```

Elasticsearch uses these local mappings:

```text
setup/elasticsearch/config/elasticsearch.yml -> /usr/share/elasticsearch/config/elasticsearch.yml (read-only)
setup/elasticsearch/data/ -> /usr/share/elasticsearch/data
```

## Reset data

This is destructive and permanently deletes only the contents beneath these development data directories:

```text
setup/mysql/data/
setup/redis/data/
setup/mongo/db/
setup/rabbitmq/data/
setup/elasticsearch/data/
```

This list defines the current reset boundary; it does **not** claim that RabbitMQ or Elasticsearch data was deleted during any earlier reset. Run the following procedure from the repository root. It first requires all five corresponding services to stop successfully, resolves and checks each exact target without following a target symlink, displays the resolved paths, and requires an exact confirmation phrase. It preserves every parent directory and any `.gitkeep` placeholder while deleting the other entries, including hidden entries.

```bash
set -eu
docker compose stop mysql redis mongo rabbitmq elasticsearch
python3 - <<'PY'
from pathlib import Path
import os
import shutil

root = Path.cwd().resolve(strict=True)
relative_targets = (
    Path("setup/mysql/data"),
    Path("setup/redis/data"),
    Path("setup/mongo/db"),
    Path("setup/rabbitmq/data"),
    Path("setup/elasticsearch/data"),
)
targets = []
for relative in relative_targets:
    expected = root / relative
    if expected.is_symlink():
        raise SystemExit(f"refusing symlink target: {expected}")
    resolved = expected.resolve(strict=True)
    if resolved != expected or os.path.commonpath((root, resolved)) != str(root):
        raise SystemExit(f"target failed exact containment check: {resolved}")
    if not resolved.is_dir():
        raise SystemExit(f"target is not a directory: {resolved}")
    targets.append(resolved)

print("The following directory contents will be permanently deleted (except .gitkeep):")
for target in targets:
    print(target)
confirmation = input("Type RESET FIVE DATA DIRECTORIES to continue: ")
if confirmation != "RESET FIVE DATA DIRECTORIES":
    raise SystemExit("reset cancelled")

# Complete a second validation pass over all five targets before deleting any target.
for target in targets:
    if target.is_symlink() or target.resolve(strict=True) != target:
        raise SystemExit(f"target changed after confirmation: {target}")
    if os.path.commonpath((root, target)) != str(root) or not target.is_dir():
        raise SystemExit(f"target failed final containment check: {target}")

# Only after every target passes the second validation may deletion begin.
for target in targets:
    for child in target.iterdir():
        if child.name == ".gitkeep":
            continue
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()
    print(f"cleared {target} (preserved .gitkeep if present)")
PY
```

If the stop command or any exact-path check fails, the shell exits before confirmation or deletion. Do not use `docker compose down -v`, a broad `rm`, or a deletion command aimed at `setup/`; those operations exceed this reset boundary. Do not start MongoDB 8.3 against old MongoDB 5 data files. If WiredTiger rejects the bind mount on macOS, stop the stack and use a Docker named volume for MongoDB's `/data/db` instead of reusing or upgrading the old files in place; restore or migrate data only through a documented, compatible MongoDB procedure.

## Service versions

| Service | Image or base image | Loopback endpoint |
| --- | --- | --- |
| Nginx | `nginx:1.30.4-trixie` | `127.0.0.1:80`, `127.0.0.1:443` |
| Redis | `redis:8.10.1` | `127.0.0.1:6379` |
| MySQL | `mysql:9.7.2` | `127.0.0.1:3306` |
| MongoDB | `mongo:8.3.8-noble` | `127.0.0.1:27017` |
| RabbitMQ | `rabbitmq:4.3.5-management` | `127.0.0.1:5672`, `127.0.0.1:15672` |
| Elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:9.5.2` | `http://127.0.0.1:9200` |

All services are intended for local personal development. Review the Compose configuration and local credentials before starting them.
