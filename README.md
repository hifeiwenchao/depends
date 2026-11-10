# depends

用于远程主机上的个人开发服务栈，提供 NGINX、MySQL、Redis、MongoDB、RabbitMQ 和 Elasticsearch。多个项目共用本 Compose 的 NGINX 容器作为统一入口，各项目自行维护站点配置，部署时放入 `setup/nginx/conf/conf.d/`。本配置使用 Compose 的简写端口映射（例如 `80:80`），默认将已发布的服务端口绑定到所有宿主机网络接口，允许外部客户端访问；仍**不适用于生产环境**。操作者必须控制 Docker 主机及其网络边界。

## 环境要求

- Docker Engine 或 Docker Desktop。
- Docker Compose v2.17.2 或更高版本（使用 `docker compose`，而不是旧版的 `docker-compose` 命令）。
- 本地仓库副本。
- 远程主机的公网或私网地址、DNS（如有），以及已放行的云安全组和主机防火墙规则。
- 在 Docker Desktop 上运行 Elasticsearch 时，共享仓库路径，为 Docker Desktop Linux 虚拟机分配至少 4 GiB 内存，并在该虚拟机内确保 `vm.max_map_count` 至少为 `1048576`，然后再启动。

## 配置

复制示例环境文件，并在本地填写所需值：

```bash
cp .env.example .env
```

在 `.env` 中设置以下本地凭据：`MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD`、`REDIS_PASSWORD`、`MONGO_INITDB_ROOT_PASSWORD`、`RABBITMQ_DEFAULT_PASS` 和 `ELASTIC_PASSWORD`。每个密码都必须使用 URL 安全字符集 `[A-Za-z0-9._~-]+` 生成；验证示例会将 `.env` 作为 POSIX shell 脚本加载，Redis ACL 生成也会强制使用同一字符集。`RABBITMQ_DEFAULT_USER` 默认为 `dev`；对于普通的容器网络客户端，不要使用 `guest`。将 `.env` 保留在本地：不要提交它，也不要把凭据粘贴到 issue 或聊天记录中。不要暴露或分享其内容。

此配置会将 MySQL、Redis、MongoDB、RabbitMQ AMQP/Management 和 Elasticsearch HTTP 端口发布到所有网络接口。Compose 中省略宿主机 IP 的映射（例如 `3306:3306`）等价于 IPv4 的 `0.0.0.0:3306:3306`。请在云安全组和主机防火墙中限制来源 IP；不要把这些端口直接暴露给不受信任的公网。远程访问必须使用强凭据；生产环境还应通过 VPN、反向代理或其他受控网络边界提供 TLS 和访问控制。

Compose 文件**不会自动创建 MySQL 应用数据库**。如果应用需要，请在 MySQL 健康运行后显式创建应用数据库。

MySQL 仅在初始化空的 `setup/mysql/data/` 时应用 `MYSQL_ROOT_PASSWORD`、`MYSQL_USER` 和 `MYSQL_PASSWORD`。在已初始化的数据目录中修改 `.env` 不会轮换账户；请使用经过身份验证的 `ALTER USER` 语句进行轮换。MongoDB 同样仅在初始化空的 `setup/mongo/db/` 时应用 `MONGO_INITDB_ROOT_USERNAME` 和 `MONGO_INITDB_ROOT_PASSWORD`；之后修改 `.env` 不会轮换已持久化的用户，因此请使用经过身份验证的 MongoDB 用户管理命令进行轮换。

RabbitMQ 首次以空数据目录启动时，会创建配置的用户并使用默认 `/` vhost；它不会创建特定于应用的 vhost。RabbitMQ 引导环境变量只在初始化期间生效，因此之后修改它们不会轮换持久化在 broker 数据中的凭据。Elasticsearch 同样只在初始化空数据时应用 `ELASTIC_PASSWORD`。对于已初始化的集群，修改环境变量不会轮换内置 `elastic` 密码；请改用 `elasticsearch-reset-password`。

## Linux 开发工具安装

`scripts/install-tools.sh` 用于在 Debian/Ubuntu、Fedora/RHEL/CentOS 或 Arch Linux 上安装稳定版 Git、zsh、Node.js/npm、Supervisor、Miniconda、Docker Engine 和 Docker Compose。脚本需要 root 或 `sudo`，默认会为当前执行用户设置 Oh My Zsh 和 Miniconda，并将目标用户的默认登录 shell 设置为 zsh；如果以 root 执行，也可以直接安装到 root 用户环境：

```bash
TARGET_USER="$USER" bash scripts/install-tools.sh --dry-run
sudo env TARGET_USER="$USER" bash scripts/install-tools.sh
```

脚本使用 Docker 官方 `stable` 软件源；如果检测到 `docker` 命令和 `docker compose version` 都可用，会跳过 Docker 软件包和仓库下载，只执行服务启用及用户组处理；设置 `DOCKER_REINSTALL=1` 可强制重新安装。安装脚本默认将 Docker Hub 镜像源配置为 `https://docker.m.daocloud.io`，会先备份已有的 `/etc/docker/daemon.json`，合并保留其他配置后重启 Docker；设置 `DOCKER_REGISTRY_MIRROR=""` 可关闭此行为，也可以指定已批准的 HTTPS 镜像源。该镜像加速只影响 Docker Hub，Elasticsearch 仍从 `docker.elastic.co` 拉取。APT 和 Arch 使用系统包安装 Supervisor；Rocky/RHEL/Fedora 在系统仓库没有 Supervisor 时使用 Python 3 pip 安装 PyPI 稳定版，可通过 `SUPERVISOR_VERSION` 固定版本。安装完成后会生成 `/etc/supervisord.conf`、`/etc/supervisord.d/*.ini` 配置目录和 `/etc/systemd/system/supervisord.service`，自动启用并启动服务；Supervisor 的 HTTP 控制端点只监听 `127.0.0.1:9001`，可直接执行 `supervisorctl status` 查看用户程序。已有的 Supervisor 配置会保留，不会被脚本覆盖。APT 环境可以通过 `DOCKER_CE_VERSION` 固定 Docker CE 包版本。Rocky/RHEL 系统会先用 `curl` 下载 RPM 仓库定义，并默认让 DNF/YUM 使用 IPv4（`DOCKER_RPM_IP_RESOLVE=4`）、单线程下载（`DOCKER_RPM_MAX_PARALLEL_DOWNLOADS=1`）、120 秒超时、10 次重试和关闭 fastestmirror，以规避部分主机到 Docker CDN 的连接重置问题；这些参数都可通过同名环境变量覆盖（`auto` 会映射到 DNF/YUM 的 `whatever` 模式）。脚本会输出明确的 DNS/TLS/代理错误；如果服务器无法访问 Docker 官方站点，可通过 `DOCKER_RPM_REPO_URL` 指向已批准的 HTTPS 镜像。Miniconda 默认使用官方稳定通道 `latest` 安装器，并从官方目录索引提取并校验对应安装器的 SHA-256；如需固定目标版本，可通过 `MINICONDA_VERSION` 指定版本，通过 `MINICONDA_PREFIX` 覆盖安装目录。若需可审计复现，请另外记录并校验该版本的固定 SHA-256。官方移除某个指定版本后，下载会失败并显示对应的完整 installer/checksum URL（通常表现为 HTTP 404）。Oh My Zsh 会安装 `zsh-syntax-highlighting` `0.8.0`、`zsh-autosuggestions` `v0.7.1` 和 Powerlevel10k `v1.20.0`，复制官方 lean Prompt 配置到 `~/.p10k.zsh`，并在 `~/.zshrc` 中追加受标记管理的主题/插件加载块；版本可分别通过 `ZSH_SYNTAX_HIGHLIGHTING_REF`、`ZSH_AUTOSUGGESTIONS_REF` 和 `POWERLEVEL10K_REF` 覆盖。重复运行会保留已有的 Oh My Zsh、`.zshrc`、已有 Supervisor 配置和 Miniconda 配置。Docker 安装完成后需要重新登录，使新的 `docker` 用户组权限生效。

如需卸载这些开发工具，使用 `scripts/uninstall-tools.sh`。脚本会先显示范围并要求输入 `REMOVE DEV TOOLS`；默认保留 Docker 镜像、容器、卷、构建缓存、Docker 软件源、`.oh-my-zsh` 和 `.p10k.zsh`，也不会删除 `setup/` 下的 Compose 数据。确认环境不再需要这些数据和用户配置时，可执行：

```bash
sudo env TARGET_USER="$USER" bash scripts/uninstall-tools.sh \
  --purge-user-config --purge-docker-data --remove-docker-repo
```

`--dry-run` 可先预览操作；`--purge-docker-data` 会永久删除 `/var/lib/docker` 和 `/var/lib/containerd`，请勿与项目数据重置流程混用。

卸载时会先停止并禁用 `supervisord`，删除脚本生成的 systemd 单元和带管理标记的 `/etc/supervisord.conf`；用户自行创建的 Supervisor 配置会保留。

## 多项目共用 Compose NGINX

本项目负责统一运行 `nginx:1.30.4-trixie` 和管理公共配置，各应用项目负责自己的域名、路由及上游配置。部署关系如下：

| 内容 | 维护位置 | 部署位置 |
| --- | --- | --- |
| NGINX 主配置 | 本仓库 `setup/nginx/conf/nginx.conf` | 容器 `/etc/nginx/nginx.conf` |
| 项目 A 站点配置 | 项目 A 仓库，例如 `deploy/nginx.conf` | `setup/nginx/conf/conf.d/project-a.conf` |
| 项目 B 站点配置 | 项目 B 仓库，例如 `deploy/nginx.conf` | `setup/nginx/conf/conf.d/project-b.conf` |

整个 `setup/nginx/conf/` 目录只读挂载到容器 `/etc/nginx/`，主配置会加载 `conf.d/*.conf`。`default.conf` 是本项目维护的通用欢迎页；项目专用的旧代理配置已删除，本仓库不再维护具体应用的代理配置。部署进来的其他 `.conf` 已加入 `.gitignore`，其源文件应在各自项目仓库中版本管理。旧的 `setup/nginx/html`、`static`、`media` 和 `ssl` 目录仍保留，默认不挂载。

### 共享网络与部署顺序

NGINX 使用固定名称的 Docker 网络 `depends_proxy`，由本 Compose 创建；中间件继续使用 `main` 网络。先启动统一入口以创建共享网络：

```bash
cd /opt/apps/depends
docker compose config --quiet
docker compose up -d --wait --wait-timeout 60 nginx
```

各项目在自己的 Compose 中声明该网络为 external，并为 Web/API 服务设置唯一的网络别名。以下为项目 A 的配置片段，合并到该项目原有的 `image` 或 `build` 等配置中；假设应用在容器内监听 `0.0.0.0:8000`：

```yaml
services:
  web:
    networks:
      proxy:
        aliases:
          - project-a-web

networks:
  proxy:
    external: true
    name: depends_proxy
```

若应用还有自己的数据库网络，可同时保留该网络，仅将对外提供 HTTP 的服务加入 `depends_proxy`。应用不需要发布宿主机的 HTTP 端口，也不要再占用宿主机 `80/443`；NGINX 通过 `project-a-web:8000` 访问容器内的端口。各项目的网络别名、NGINX upstream 名和域名均须唯一，不要共用 `web` 等泛化上游名称。

### 各项目维护的站点配置

项目 A 可将下例保存为自己仓库的 `deploy/nginx.conf`，部署时改名为 `project-a.conf`。将域名、别名和端口替换为实际值：

```nginx
upstream project_a_web {
    zone project_a_web 64k;
    resolver 127.0.0.11 valid=10s ipv6=off;
    server project-a-web:8000 resolve;
}

server {
    listen 80;
    server_name project-a.example.com;

    client_max_body_size 20m;

    location / {
        proxy_pass http://project_a_web;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

固定镜像版本支持上述动态 DNS 配置：`127.0.0.11` 是 Docker 内置 DNS，`resolve` 会更新重建后的应用容器地址。某个应用尚未启动时，其站点暂时返回 `502`，不会因为上游域名不存在而阻止整个 NGINX 启动。NGINX 健康检查验证配置是否有效，应用健康仍需单独检查。

容器中的 `127.0.0.1` 指向 NGINX 容器自身，不能沿用宿主机 NGINX 的 `proxy_pass http://127.0.0.1:8081`。本示例适用于 Docker 应用；直接运行在宿主机的应用需另行配置从容器可访问的宿主机地址和应用监听地址。

### 投放配置与重载

先启动项目上游，再从项目仓库复制配置到远端的统一目录。更新已有站点前先将原文件备份为 `.conf.bak` 等不以 `.conf` 结尾的文件；每次只操作本项目自己的文件，不要清空整个 `conf.d` 或覆盖其他项目配置。

在远端执行以下示例，源路径按应用的实际部署位置替换：

```bash
cd /opt/apps/depends
# 更新已有站点时，先备份当前配置。
if [ -f setup/nginx/conf/conf.d/project-a.conf ]; then
  cp -p setup/nginx/conf/conf.d/project-a.conf setup/nginx/conf/conf.d/project-a.conf.bak
fi
# 先写入不参与加载的临时文件，再在同一目录内原子替换。
install -m 0644 /opt/apps/project-a/deploy/nginx.conf setup/nginx/conf/conf.d/project-a.conf.next &&
mv setup/nginx/conf/conf.d/project-a.conf.next setup/nginx/conf/conf.d/project-a.conf &&
docker compose exec -T nginx nginx -t &&
docker compose exec -T nginx nginx -s reload
```

只有配置检查通过才重载。检查失败时，恢复该站点的备份；如果是首次添加，将新文件移出 `conf.d`，然后重新检查。运行中的 worker 会继续使用上次已加载的配置，不要在恢复前重启 NGINX。删除应用时也只移走对应的 `.conf`，检查通过后重载。

将真实域名的 DNS 记录指向服务器，并验证对应站点，例如：

```bash
curl --fail --silent --show-error -H 'Host: project-a.example.com' http://127.0.0.1/ >/dev/null
docker compose logs --tail=50 nginx
```

示例验证假设应用存在 `/` 路由，API 请改为实际健康检查路径。WebSocket、静态文件和超时等设置由各项目自行维护；静态文件路径和证书路径必须在容器内可访问。

Compose 发布 `80:80` 和 `443:443`，并将 `setup/nginx/certs/` 整个目录只读挂载到 `/etc/ssl/depends/`。默认欢迎页仍只有 HTTP；在证书签发和项目 TLS 配置部署前，容器不会监听 HTTPS。新仓库无需预置证书也能启动。公共配置随镜像版本更新时，须保留已部署的项目站点文件和本地证书。

### Let's Encrypt 通配符证书

`example.com` 与 `*.example.com` 使用同一张证书，后者覆盖 `www.example.com`、`admin.example.com`、`xxx.example.com` 等任意一级子域名。它不覆盖 `a.b.example.com`，也不会自动创建域名的 DNS 记录；每个实际站点仍需配置 A/AAAA 记录及自己的 NGINX 路由。

通配符必须使用 DNS-01 验证。本服务器采用官方 `acme.sh` 的 `dns_ali` 插件，明确指定 Let's Encrypt 签发；阿里云 API 凭据由有域名 DNS 管理权限的 RAM 用户提供，保存在服务器 `/root/.config/acme/aliyun.env`（目录权限 `700`、文件权限 `600`），使用 `Ali_Key` 和 `Ali_Secret` 变量。不要将凭据放入项目 `.env`、站点配置、Git 或日志，也不要在聊天中发送。ACME 账户及续期状态保存在 `/root/.acme.sh/`，仅 root 可访问。

#### 完整的申请、部署和续期流程

以下步骤适用于新服务器。示例固定使用 `acme.sh` `3.1.6`、阿里云 DNS-01、Let's Encrypt 生产 CA、ECC P-256，以及本项目的 `/opt/apps/depends` 路径。命令以 root 执行；如果服务器已有 acme.sh，先执行 `acme.sh --version`，不要覆盖已有账户目录。

1. 安装 acme.sh，并关闭它自带的 cron。续期由后文的 systemd timer 统一管理：

   ```bash
   set -eu
   ACME_VERSION=3.1.6
   ACME_HOME=/root/.acme.sh
   TMP_DIR=$(mktemp -d)
   trap 'rm -rf "$TMP_DIR"' EXIT
   curl --fail --silent --show-error --location --retry 3 \
     "https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/${ACME_VERSION}" \
     --output "$TMP_DIR/acme.sh.tar.gz"
   tar -xzf "$TMP_DIR/acme.sh.tar.gz" -C "$TMP_DIR"
   cd "$TMP_DIR/acme.sh-${ACME_VERSION}"
   sh ./acme.sh --install --home "$ACME_HOME" --nocron --noprofile
   chmod 700 "$ACME_HOME"
   "$ACME_HOME/acme.sh" --version
   "$ACME_HOME/acme.sh" --uninstall-cronjob --home "$ACME_HOME" || true
   ```

2. 准备阿里云 RAM 用户凭据。RAM 用户只授予 `example.com` DNS 记录管理权限；文件不要使用 `export`，这样可以同时被 acme.sh 和 systemd `EnvironmentFile` 读取：

   ```bash
   install -d -m 700 /root/.config/acme
   cat >/root/.config/acme/aliyun.env <<'EOF'
   # AliDNS DNS-01 credentials; root-only, do not commit.
   Ali_Key=YOUR_ALIYUN_ACCESS_KEY_ID
   Ali_Secret=YOUR_ALIYUN_ACCESS_KEY_SECRET
   EOF
   chmod 600 /root/.config/acme/aliyun.env
   ```

   手动申请前只在当前 shell 中加载凭据，完成后立即清除：

   ```bash
   set -a
   . /root/.config/acme/aliyun.env
   set +a
   ```

3. 先使用 Let's Encrypt staging CA 测试 DNS 权限。staging 证书不受浏览器信任，且使用独立配置和证书目录，不会污染正式账户：

   ```bash
   /root/.acme.sh/acme.sh --issue \
     --server https://acme-staging-v02.api.letsencrypt.org/directory \
     --dns dns_ali \
     --home /root/.acme.sh \
     --config-home /root/.acme-staging \
     --cert-home /root/.acme-staging/certs \
     --dnssleep 60 \
     --keylength ec-256 \
     -d example.com \
     -d '*.example.com'
   ```

   确认输出显示 DNS 验证和签发成功。传播较慢时增加 `--dnssleep`；不要在 staging 失败时反复请求正式证书。

4. 注册 Let's Encrypt 生产账户并申请正式证书：

   ```bash
   /root/.acme.sh/acme.sh --register-account \
     --server letsencrypt \
     -m admin@example.com

   /root/.acme.sh/acme.sh --issue \
     --server letsencrypt \
     --dns dns_ali \
     --home /root/.acme.sh \
     --dnssleep 60 \
     --keylength ec-256 \
     -d example.com \
     -d '*.example.com'
   unset Ali_Key Ali_Secret
   ```

   生产证书保存在 `/root/.acme.sh/example.com_ecc/`。必须确认 CA、域名和有效期：

   ```bash
   openssl x509 -in /root/.acme.sh/example.com_ecc/fullchain.cer \
     -noout -issuer -dates -ext subjectAltName
   ```

   输出应包含 `DNS:example.com`、`DNS:*.example.com` 和 Let's Encrypt 签发者；如果出现 `STAGING`，不要部署到生产 NGINX。

5. 把证书复制到项目的 Git 忽略目录，并记录续期后的 NGINX reload 命令。`--install-cert` 会立即执行一次 reload 命令，因此应先确保 Compose NGINX 已启动；证书目录必须使用整体目录挂载：

   ```bash
   CERT_DIR=/opt/apps/depends/setup/nginx/certs/example.com
   install -d -m 700 "$CERT_DIR"
   /root/.acme.sh/acme.sh --install-cert \
     --home /root/.acme.sh \
     --ecc \
     -d example.com \
     --key-file "$CERT_DIR/privkey.pem" \
     --fullchain-file "$CERT_DIR/fullchain.pem" \
     --reloadcmd 'docker compose --project-directory /opt/apps/depends -f /opt/apps/depends/docker-compose.yml exec -T nginx nginx -t && docker compose --project-directory /opt/apps/depends -f /opt/apps/depends/docker-compose.yml exec -T nginx nginx -s reload'
   chmod 600 "$CERT_DIR/privkey.pem"
   chmod 644 "$CERT_DIR/fullchain.pem"
   ```

   NGINX 容器内的证书路径是 `/etc/ssl/depends/example.com/`。各项目把自己的 TLS 站点配置部署到 `setup/nginx/conf/conf.d/`，然后检查并 reload：

   ```bash
   cd /opt/apps/depends
   docker compose exec -T nginx nginx -t
   docker compose exec -T nginx nginx -s reload
   ```

   首次增加 `443:443`、证书挂载或 TLS 默认站点时才需要 `docker compose up -d --force-recreate --no-deps nginx`；仅替换证书文件不需要重建容器。

6. 手动续期时不要使用 `--force` 作为日常命令。普通续期会在证书未接近到期时跳过；`--force` 只用于专门测试续期链路：

   ```bash
   set -a
   . /root/.config/acme/aliyun.env
   set +a
   /root/.acme.sh/acme.sh --renew-all --home /root/.acme.sh
   # 只续期本证书：
   # /root/.acme.sh/acme.sh --renew -d example.com --ecc --home /root/.acme.sh
   # 强制测试（会消耗 CA/DNS 请求额度）：
   # /root/.acme.sh/acme.sh --renew -d example.com --ecc --force --home /root/.acme.sh
   unset Ali_Key Ali_Secret
   ```

   直接执行 `--renew` 时，未到续期时间可能返回代码 `2` 表示跳过；systemd 使用的 `--cron` 会把这种正常跳过视为成功。续期成功后，`--install-cert` 保存的 reload hook 会安装新文件、执行 `nginx -t`，再 reload NGINX。

签发后通过 `acme.sh --install-cert` 将证书部署到以下路径：

| 宿主机 | NGINX 容器 |
| --- | --- |
| `setup/nginx/certs/example.com/fullchain.pem` | `/etc/ssl/depends/example.com/fullchain.pem` |
| `setup/nginx/certs/example.com/privkey.pem` | `/etc/ssl/depends/example.com/privkey.pem` |

`certs/` 除 `.gitkeep` 外全部被 Git 忽略；私钥权限为 `600`。不要将新证书写入历史 `setup/nginx/ssl/` 中已受版本管理的文件。挂载整个目录保证续期替换文件后，容器可以看到新证书；不要改为逐个 PEM 文件的 bind mount。

各项目仍在自己维护的站点配置中启用 HTTPS。保留其实际 `server_name`、路由和上游配置，并在 `server` 中增加：

```nginx
listen 443 ssl;
ssl_certificate /etc/ssl/depends/example.com/fullchain.pem;
ssl_certificate_key /etc/ssl/depends/example.com/privkey.pem;
ssl_protocols TLSv1.2 TLSv1.3;
```

仅在证书文件已存在时投放 TLS 站点。新增站点或更换证书后先执行 `nginx -t`，再执行 `nginx -s reload`；首次增加端口和挂载时需仅重建 NGINX 容器。

服务器使用 `depends-acme-renew.timer` 每天触发两次续期检查并加入随机延迟。只有接近到期时才申请新证书；成功安装新证书后，部署钩子会检查并重载本项目的 NGINX。安装 acme.sh 时必须关闭其自带 cron，避免重复申请。

创建 root-only 的 systemd 服务和 timer：

```bash
cat >/etc/systemd/system/depends-acme-renew.service <<'EOF'
[Unit]
Description=Renew Let's Encrypt certificates for depends NGINX
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
User=root
UMask=0077
WorkingDirectory=/opt/apps/depends
EnvironmentFile=/root/.config/acme/aliyun.env
ExecStart=/root/.acme.sh/acme.sh --cron --home /root/.acme.sh
TimeoutStartSec=20min
EOF

cat >/etc/systemd/system/depends-acme-renew.timer <<'EOF'
[Unit]
Description=Check depends Let's Encrypt certificate renewal twice daily

[Timer]
OnCalendar=*-*-* 03,15:00:00
RandomizedDelaySec=1h
Persistent=true
Unit=depends-acme-renew.service

[Install]
WantedBy=timers.target
EOF

chmod 644 /etc/systemd/system/depends-acme-renew.service /etc/systemd/system/depends-acme-renew.timer
systemd-analyze verify /etc/systemd/system/depends-acme-renew.service /etc/systemd/system/depends-acme-renew.timer
systemctl daemon-reload
systemctl enable --now depends-acme-renew.timer
systemctl start depends-acme-renew.service
systemctl show depends-acme-renew.service --property=Result --property=ExecMainStatus
systemctl list-timers depends-acme-renew.timer --no-pager
```

`Result=success` 和 `ExecMainStatus=0` 表示本次检查成功。定时任务未到续期窗口时不会申请新证书；成功续期时，`--install-cert` 保存的 reload hook 会先执行 `nginx -t`，再 reload。检查并删除重复的 acme.sh cron：

```bash
systemctl list-timers depends-acme-renew.timer
systemctl status depends-acme-renew.service --no-pager
journalctl -u depends-acme-renew.service --since '7 days ago' --no-pager
openssl x509 -in /opt/apps/depends/setup/nginx/certs/example.com/fullchain.pem -noout -issuer -dates -ext subjectAltName
crontab -l
```

远端已部署的通配符 TLS 入口配置属于运行环境文件，不提交本仓库。证书只提供 TLS 身份验证；具体域名的页面和反向代理仍由各项目自己的配置决定。

### 从宿主机 NGINX 切回容器

如果此前已安装并启动宿主机 NGINX，先检查容器配置，再停用宿主机服务以释放端口，只启动本项目的 NGINX：

```bash
cd /opt/apps/depends
docker compose config --quiet
docker compose run --rm --no-deps nginx nginx -t
sudo systemctl disable --now nginx
docker compose up -d --wait --wait-timeout 60 nginx
curl --fail --silent --show-error http://127.0.0.1/ >/dev/null
```

全新部署无需执行停用宿主机服务的步骤。若切换失败，先执行 `docker compose stop nginx` 释放端口，再执行 `sudo systemctl enable --now nginx` 恢复原入口。切换不需要停止或重建数据库，也不删除 `/etc/nginx/` 和 `setup/` 下的文件。

## 启动

先验证渲染后的 Compose 配置，启动共享 NGINX，再逐个启动中间件：

```bash
docker compose config --quiet
docker compose up -d --wait --wait-timeout 60 nginx
docker compose up -d redis
docker compose up -d mongo
docker compose up -d mysql
docker compose up -d rabbitmq
docker compose up -d elasticsearch
docker compose ps
```

按上述顺序逐个启动并验证有状态服务；等待每个服务变为 healthy 后再继续。启动 Elasticsearch 时，Compose 会先运行 `elasticsearch-permissions` 一次性初始化服务，以 root 身份将 `setup/elasticsearch/data/` 设置为容器用户 `1000:0` 可写，然后再启动 Elasticsearch；该服务不会删除或重建已有数据。六个业务服务使用下方列出的精确版本，都应处于运行状态，并最终报告 `healthy`；权限初始化服务显示 `Exited (0)` 属于正常状态。

## 验证

检查服务状态，并等待每个服务的健康检查通过：

```bash
docker compose ps
docker compose exec -T nginx nginx -t
curl --fail --silent --show-error http://127.0.0.1/ >/dev/null
```

确认 Compose 发布的宿主机端口为 `80`、`443`、`3306`、`6379`、`27017`、`5672`、`15672` 和 `9200`，并且这些端口默认绑定所有网络接口。RabbitMQ 的 Prometheus 端口 `15692` 保持为容器内部端口，Elasticsearch 传输端口 `9300` 不得发布到主机。默认 NGINX 提供官方欢迎页，添加站点后还需按域名单独验证转发。

进行组件检查时，请使用经过身份验证的命令，并避免将密码写入 shell 历史或日志。示例：

```bash
# 仅在此 shell 中导出 .env。先禁用跟踪，避免回显值。
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

Redis 应返回 `PONG`；MySQL 应报告其正在运行；MongoDB 应成功响应 ping 命令。RabbitMQ 应通过 broker 诊断，并且其经过身份验证的管理 API 已发布到宿主机所有网络接口的 `15672` 端口。Elasticsearch 应在 `http://服务器地址:9200` 上要求 `elastic` 密码，并达到黄色或绿色的单节点集群健康状态。当前 Elasticsearch 使用明文 HTTP；远程部署时必须通过防火墙、VPN 或反向代理限制访问，生产环境应启用 TLS。确认报告的组件版本与下方版本一致，并在使用该服务栈前确认六个业务服务都处于 healthy 状态。

RabbitMQ 使用以下本地映射：

```text
setup/rabbitmq/conf/rabbitmq.conf -> /etc/rabbitmq/rabbitmq.conf (只读)
setup/rabbitmq/conf/enabled_plugins -> /etc/rabbitmq/enabled_plugins (只读)
setup/rabbitmq/data/ -> /var/lib/rabbitmq
```

Elasticsearch 使用以下本地映射：

```text
setup/elasticsearch/config/elasticsearch.yml -> /usr/share/elasticsearch/config/elasticsearch.yml (只读)
setup/elasticsearch/data/ -> /usr/share/elasticsearch/data
```

## 重置数据

此操作具有破坏性，并会永久删除以下开发数据目录中的**全部内容**：

```text
setup/mysql/data/
setup/redis/data/
setup/mongo/db/
setup/rabbitmq/data/
setup/elasticsearch/data/
```

此列表定义当前的重置边界；它**不表示** RabbitMQ 或 Elasticsearch 的数据在任何先前的重置中已被删除。请从仓库根目录运行以下流程。流程首先要求对应的五个服务全部成功停止，然后解析并检查每个精确目标且不跟随目标符号链接，显示解析后的路径，并要求输入精确的确认短语。它会保留所有父目录和任何 `.gitkeep` 占位文件，同时删除其他条目，包括隐藏条目。

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

如果停止命令或任一精确路径检查失败，shell 会在确认或删除前退出。不要使用 `docker compose down -v`、宽泛的 `rm`，或针对 `setup/` 的删除命令；这些操作超出了上述重置边界。不要让 MongoDB 8.3 使用旧的 MongoDB 5 数据文件启动。如果 WiredTiger 在 macOS 上拒绝绑定挂载，请停止服务栈，并为 MongoDB 的 `/data/db` 使用 Docker 命名卷，而不是在原位置复用或升级旧文件；只能通过有文档记录且兼容的 MongoDB 流程恢复或迁移数据。

## 服务版本

| 服务 | 镜像或基础镜像 | 宿主机端口映射 |
| --- | --- | --- |
| NGINX | `nginx:1.30.4-trixie` | `80:80`、`443:443` |
| Redis | `redis:8.10.1` | `6379:6379` |
| MySQL | `mysql:9.7.2` | `3306:3306` |
| MongoDB | `mongo:8.3.8-noble` | `27017:27017` |
| RabbitMQ | `rabbitmq:4.3.5-management` | `5672:5672`、`15672:15672` |
| Elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:9.5.2` | `9200:9200` |

所有服务都面向远程个人开发，已发布的端口默认绑定所有网络接口。应用通过共享网络接入 NGINX，不会改变本项目中间件端口的访问范围。启动前请检查 Compose 配置、本地凭据以及云安全组和主机防火墙规则。
