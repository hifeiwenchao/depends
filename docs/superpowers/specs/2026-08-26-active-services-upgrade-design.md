# Active Services Upgrade Design

## Context

This repository provides Docker Compose configuration for foundational services. The six active services are Nginx, MySQL, Redis, MongoDB, RabbitMQ, and Elasticsearch. Ghost, WordPress, Kafka, ZooKeeper, Zabbix, and File Browser are outside this upgrade.

The stack targets a personal development machine. Runtime data in the five reset directories for MySQL, Redis, MongoDB, RabbitMQ, and Elasticsearch is disposable and requires neither migration nor backward compatibility. The upgrade initializes each stateful service from an empty data directory.

## Goals

- Upgrade active services to exact, currently available stable image versions as verified on 2026-08-26.
- Reinitialize stateful services without interpreting old data formats.
- Keep database ports accessible from the development host but not from external interfaces.
- Remove committed runtime credentials from Compose and Redis configuration.
- Replace legacy version-specific configuration with current minimal configuration.
- Add health checks, bounded log rotation, validation instructions, and concise operator documentation.

## Non-goals

- Preserve, migrate, back up, or restore existing database/cache data.
- Upgrade inactive or commented services.
- Make this stack production-ready.
- Create a default MySQL application database or grant `dev` access to one.
- Delete tracked TLS material or rotate unrelated historical secrets in this change.

## Target versions

| Service | Current | Target |
|---|---:|---:|
| Nginx | 1.15.6 | `nginx:1.30.4-trixie` |
| MySQL | 8.0.32 | `mysql:9.7.2` |
| Redis | 5.0.0 | `redis:8.10.1` |
| MongoDB | 5.0.3 | `mongo:8.3.8-noble` |
| RabbitMQ | Not active | `rabbitmq:4.3.5-management` |
| Elasticsearch | Not active | `docker.elastic.co/elasticsearch/elasticsearch:9.5.2` |

Exact patch tags are used instead of moving tags. MySQL 9.7.3 exists as an Oracle security release, but the Docker Official `mysql:9.7.3` tag was not available when this design was written; `mysql:9.7.2` is the newest verified pullable Docker Official Image tag.

## Compose architecture

`docker-compose.yml` remains the single stack entry point. The obsolete top-level `version` field is removed. A top-level YAML extension defines one bounded `json-file` logging policy (`100m`, three files), reused by all six services.

All services remain on the `main` network and use Compose service names for container-to-container communication. Development host ports bind only to loopback:

- Nginx: `127.0.0.1:80:80`, `127.0.0.1:443:443`
- MySQL: `127.0.0.1:3306:3306`
- Redis: `127.0.0.1:6379:6379`
- MongoDB: `127.0.0.1:27017:27017`
- RabbitMQ: `127.0.0.1:5672:5672`, `127.0.0.1:15672:15672`
- Elasticsearch: `127.0.0.1:9200:9200`; transport remains unpublished and binds to `127.0.0.1` in the container

`restart: unless-stopped` replaces `restart: always`. Redundant `expose` and explicit aliases are removed because service-name DNS already works on the shared network.

Each service receives a health check. No service is declared healthy merely because its process exists.

## Secrets and environment

A committed `.env.example` defines names but no real credentials:

```dotenv
MYSQL_ROOT_PASSWORD=
MYSQL_USER=dev
MYSQL_PASSWORD=
REDIS_USERNAME=default
REDIS_PASSWORD=
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=
RABBITMQ_DEFAULT_USER=dev
RABBITMQ_DEFAULT_PASS=
ELASTIC_PASSWORD=
TZ=Asia/Shanghai
```

`.env` and `.env.*` are ignored while `.env.example` remains tracked. Compose uses required-variable expressions for passwords. No real credential is added to source control.

MySQL receives no `MYSQL_DATABASE`. On first initialization, the entrypoint may create `dev`, but it will not grant that user privileges on an application schema. Applications or migration tooling must create databases and grants later.

Redis authentication uses an ACL file generated at container start inside `/run/redis`, a tmpfs mount. The tracked Redis configuration references that path and contains no password. The generated ACL must quote and escape the supplied username and password correctly; startup rejects line breaks in either value. Compose interpolation must not print the resulting ACL into the repository.

## Nginx design

`setup/nginx/Dockerfile` changes its base to `nginx:1.30.4-trixie`. The current paths remain compatible. Runtime Compose bind mounts continue to be authoritative, so validation must run with Compose mounts rather than only testing the image's baked copies.

`setup/nginx/conf/upstream.conf` changes include:

- Add the missing semicolon after `server_name`.
- Remove the obsolete commented `ssl off` directive.
- Replace ineffective `proxy_set_header` directives inside the uWSGI location with `uwsgi_param` equivalents for host, real IP, and forwarded scheme.
- Retain the existing upstream address, certificate paths, redirects, and static/media paths; deployment-specific host/domain cleanup is outside this upgrade.

Nginx validation includes `nginx -t`, `nginx -T`, version output, and loopback HTTP/HTTPS smoke requests. The existing certificate may make HTTPS trust validation fail, so the smoke test checks transport/configuration with `curl -k` and does not claim certificate validity.

## MySQL design

The image changes to `mysql:9.7.2`. `setup/mysql/conf/my.cnf` removes `default_authentication_plugin=mysql_native_password`, which no longer exists. New users use MySQL's default `caching_sha2_password`. `bind-address` and `skip-name-resolve` remain.

The existing `setup/mysql/data` contents are deleted only after the MySQL container is stopped and immediately before first initialization. The directory itself remains. No in-place upgrade is attempted.

The health check executes an authenticated `SELECT 1`, supplying the root password through the command's `MYSQL_PWD` environment without embedding a literal secret in Compose or placing it in a command argument. Runtime checks verify:

- Server version is 9.7.2.
- `default_authentication_plugin` is absent.
- Newly initialized users use `caching_sha2_password`.
- No application database was created by this stack.

## Redis design

The image changes to `redis:8.10.1`. The Redis 5 full sample configuration is replaced with a focused Redis 8 project configuration that includes only intentional overrides:

- Container-accessible TCP bind and port.
- Protected mode enabled.
- ACL file path under `/run/redis`.
- Standard stdout logging and non-daemon operation.
- RDB snapshot schedule.
- `stop-writes-on-bgsave-error yes`.
- `appendonly yes`.
- `appendfsync everysec`.
- `aof-use-rdb-preamble yes`.
- Current `replica-*` and `listpack` terminology where those settings are retained.
- Data directory `/data`.

The existing `setup/redis/data` contents are deleted after the service stops. Redis initializes new multipart AOF state. No Redis 5 AOF/RDB migration is attempted.

A startup wrapper generates `/run/redis/users.acl` from required environment variables, rejects characters unsafe in direct ACL tokens, and applies restrictive permissions and Redis ownership. It then invokes the Docker Official Redis image entrypoint with `redis-server` and the tracked config; the official entrypoint repairs `/data` ownership when starting as root and drops privileges to the `redis` user, which can still traverse the tmpfs directory and read the ACL. `/run/redis` is tmpfs and never persisted.

Health and smoke checks authenticate with the configured credentials and verify PING, version, ACL state, and AOF persistence settings.

## MongoDB design

The image changes to `mongo:8.3.8-noble`. The existing `setup/mongo/db` contents are deleted after the MongoDB container stops. MongoDB initializes a fresh database; no 5.0-to-8.3 FCV sequence is performed.

The design initially retains the existing host bind mount because the selected strategy explicitly keeps the repository's data-directory layout. Docker's macOS shared-filesystem behavior may be incompatible with MongoDB's memory-mapped files. If the runtime smoke test fails with WiredTiger/filesystem errors, the corrective action is to switch `/data/db` to a Docker named volume, not downgrade MongoDB.

The health check and runtime validation authenticate against `admin`, run `db.adminCommand({ping: 1})`, and report server version and feature compatibility version.

## RabbitMQ design

RabbitMQ is added as a fifth active service using the exact Docker Official Image `rabbitmq:4.3.5-management`. It targets the same personal development environment and joins the shared `main` network with stable `hostname: rabbitmq`, preserving the node identity expected by persisted Mnesia data.

Host access is loopback-only:

- AMQP: `127.0.0.1:5672:5672`
- Management UI: `127.0.0.1:15672:15672`

The service uses `restart: unless-stopped`, the shared logging policy, and `rabbitmq-diagnostics -q ping` for health. It mounts:

- `setup/rabbitmq/conf/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro`
- `setup/rabbitmq/conf/enabled_plugins:/etc/rabbitmq/enabled_plugins:ro`
- `setup/rabbitmq/data:/var/lib/rabbitmq`

`rabbitmq.conf` retains current defaults where possible and sends logs to stdout. `enabled_plugins` contains `[rabbitmq_management,rabbitmq_prometheus].`; Prometheus remains container-internal because port 15692 is not published. No separate log directory is mapped.

A fresh blank data directory is initialized with `RABBITMQ_DEFAULT_USER` and `RABBITMQ_DEFAULT_PASS` from `.env`. The default `/` vhost is used; no application-specific vhost is created. The username must not be `guest`, because the built-in guest account is restricted to localhost and is unsuitable for normal container-network clients. Changing initialization environment variables later does not rotate users in persisted data.

The design does not set `RABBITMQ_ERLANG_COOKIE`: this is a single-node local broker with no clustering or remote CLI requirement. If clustering is added later, cookie provisioning becomes a separate secret-management change.

The host data directory satisfies the explicit local-mapping requirement. On macOS, bind-mounted database performance and ownership can be less reliable than a named volume. Runtime validation must check that RabbitMQ can initialize and restart with the same node identity and data mount; if bind-mount permissions fail, correct the host directory ownership/permissions rather than running the broker as root.

Runtime checks verify RabbitMQ 4.3.5, broker health, enabled management plugin, authenticated AMQP-facing user state, Management API reachability on loopback, exact mount, and persistence across a normal container restart.

## Elasticsearch design

Elasticsearch is added as a sixth active service using Elastic's exact official image `docker.elastic.co/elasticsearch/elasticsearch:9.5.2`. It runs as one node for a personal macOS development environment.

Only the HTTP API is published at `127.0.0.1:9200:9200`. Transport port 9300 is not published because there is no second node or external transport client. The service joins `main`, uses `restart: unless-stopped`, reuses the bounded logging policy, and has a 1 GiB container memory limit. Elasticsearch auto-sizes its heap; `ES_JAVA_OPTS` is not set.

The service mounts:

- `setup/elasticsearch/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro`
- `setup/elasticsearch/data:/usr/share/elasticsearch/data`

The configuration is:

```yaml
cluster.name: depends-elasticsearch
node.name: depends-es01
network.host: 0.0.0.0
transport.host: 127.0.0.1
discovery.type: single-node
xpack.security.enabled: true
xpack.security.autoconfiguration.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

The deliberate local-development security posture is password authentication over plaintext HTTP bound only to host loopback. This avoids first-start security auto-configuration rewriting the read-only config mount and generating untracked TLS assets. It is not suitable for LAN or production exposure.

`ELASTIC_PASSWORD` is required from `.env` and initializes the built-in `elastic` user only for an empty data directory. Changing the environment later does not rotate the persisted password; use `elasticsearch-reset-password` for an initialized cluster.

The official image runs as UID:GID `1000:0`. Before startup, the data directory must be writable by that identity/group without making it world-writable. Docker Desktop must share the repository path, allocate at least 4 GiB overall, and expose `vm.max_map_count >= 1048576` inside its Linux VM.

The health check authenticates to `http://localhost:9200/_cluster/health`, waits for at least yellow status, and never prints the password. Runtime checks verify version 9.5.2, single-node health, authenticated access, loopback-only publication, exact config/data mounts, effective security/TLS settings, and persistence across a normal restart.

## Data deletion boundary

Only contents beneath these five directories are destructive targets:

- `setup/mysql/data/`
- `setup/redis/data/`
- `setup/mongo/db/`
- `setup/rabbitmq/data/`
- `setup/elasticsearch/data/`

Before deletion, implementation must:

1. Stop all five corresponding containers and abort if the stop fails.
2. Resolve and display the exact five directories.
3. Verify exact equality plus lexical and canonical containment inside the repository, rejecting symlink targets.
4. Ask for explicit confirmation naming this five-directory reset immediately before deletion.
5. Recheck every target, then delete contents including hidden entries while preserving parent directories and tracked `.gitkeep` placeholders.

No `docker compose down -v`, broad `rm` against `setup`, or deletion of log/config directories is allowed.

## Implementation and startup order

1. Add environment template, ignore rules, Compose common policy, exact versions, loopback ports, and health checks.
2. Upgrade and statically validate Nginx.
3. Replace Redis configuration and add its ACL startup wrapper.
4. Remove the MySQL authentication option.
5. Validate Compose interpolation with a temporary non-secret test environment.
6. Stop stateful services and obtain explicit deletion confirmation.
7. Clear Redis data, start Redis, and verify health/runtime state.
8. Clear MongoDB data, start MongoDB, and verify health/runtime state.
9. Clear MySQL data, start MySQL, and verify health/runtime state.
10. Start Nginx and run Nginx/HTTP smoke checks.
11. Add RabbitMQ configuration, initialize its empty local data directory, and verify broker/Management health and restart persistence.
12. Add Elasticsearch configuration, prepare its local data-directory permissions, initialize the single-node cluster, and verify authenticated health and restart persistence.
13. Document initialization, validation, data reset, RabbitMQ/Elasticsearch operation, and the macOS MongoDB fallback.

Stateful services are started and validated one at a time. A service must become healthy before work proceeds to the next service.

## Validation

Static validation runs regardless of Docker daemon availability:

- `docker compose config --quiet`
- `git diff --check`
- Assertions that exact image tags are present.
- Assertions that host ports bind to `127.0.0.1`.
- Assertions that committed files contain no selected credential literals.
- Redis configuration syntax/start check when the image can run.
- Nginx `nginx -t` when the image can run.

Runtime validation requires a working Docker daemon:

- Pull or build all exact versions.
- Start one service at a time.
- Inspect `docker compose ps` and logs.
- Wait for healthy status.
- Run component-specific version, authentication, and persistence checks.

If the daemon remains unavailable, implementation reports static validation as complete and runtime validation as explicitly pending; it must not claim the upgraded stack works at runtime.

## Failure handling and rollback

Nginx failure is handled by reverting its image/config change.

For Redis, MongoDB, or MySQL initialization failure:

1. Stop the failing container.
2. Capture logs and identify the configuration cause.
3. Correct configuration.
4. Ask again before deleting the partially initialized service data.
5. Reinitialize that service from empty storage.

A partially initialized new-version data directory must never be started under an older image. Rollback protects configuration changes, not old data, because data preservation is an explicit non-goal.

## Completion criteria

- Compose renders without warnings caused by repository configuration.
- All active images use the exact target versions.
- No active-service password is committed in Compose or Redis configuration.
- Database ports are host-accessible only through loopback.
- Nginx configuration passes `nginx -t`.
- MySQL reports 9.7.2 and current authentication plugins.
- Redis reports 8.10.1, authenticates via ACL, and uses the approved persistence policy.
- MongoDB reports 8.3.8 and passes authenticated ping.
- RabbitMQ reports 4.3.5, passes broker diagnostics, exposes Management only on loopback, and retains initialized state across restart.
- Elasticsearch reports 9.5.2, requires authentication, reaches single-node yellow/green health, exposes HTTP only on loopback, and retains its cluster identity across restart.
- All six services report healthy when runtime validation is possible.
- README documents setup, startup, validation, and destructive reset boundaries.
- Existing unrelated working-tree changes and `.DS_Store` files are not overwritten or deleted as part of this upgrade.

## Official references

- [NGINX downloads](https://nginx.org/en/download.html)
- [NGINX 1.30 changelog](https://nginx.org/en/CHANGES-1.30)
- [MySQL 9.7 release notes](https://dev.mysql.com/doc/relnotes/mysql/9.7/en/)
- [MySQL supported upgrade paths](https://dev.mysql.com/doc/refman/9.7/en/upgrade-paths.html)
- [Docker Official MySQL image](https://hub.docker.com/_/mysql)
- [Redis 8.10 release notes](https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/redisce/redisos-8.10-release-notes/)
- [Redis ACL documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/)
- [Redis persistence documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)
- [MongoDB 8.3 release notes](https://www.mongodb.com/docs/manual/release-notes/8.3)
- [MongoDB versioning](https://www.mongodb.com/docs/manual/reference/versioning/)
- [Docker Official MongoDB image](https://hub.docker.com/_/mongo)
- [RabbitMQ 4.3.5 release](https://github.com/rabbitmq/rabbitmq-server/releases/tag/v4.3.5)
- [Docker Official RabbitMQ image](https://hub.docker.com/_/rabbitmq)
- [Elastic Elasticsearch images](https://www.docker.elastic.co/r/elasticsearch/elasticsearch)
- [Configure Elasticsearch with Docker](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-configure)
