#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly MINICONDA_BASE_URL="https://repo.anaconda.com/miniconda"

DRY_RUN=0
TARGET_USER="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"
MINICONDA_VERSION="${MINICONDA_VERSION:-latest}"
MINICONDA_PREFIX="${MINICONDA_PREFIX:-}"
SUPERVISOR_VERSION="${SUPERVISOR_VERSION:-}"
SUPERVISOR_CONFIG="${SUPERVISOR_CONFIG:-/etc/supervisord.conf}"
OH_MY_ZSH_REPO="${OH_MY_ZSH_REPO:-https://github.com/ohmyzsh/ohmyzsh.git}"
OH_MY_ZSH_REF="${OH_MY_ZSH_REF:-master}"
ZSH_SYNTAX_HIGHLIGHTING_REF="${ZSH_SYNTAX_HIGHLIGHTING_REF:-0.8.0}"
ZSH_AUTOSUGGESTIONS_REF="${ZSH_AUTOSUGGESTIONS_REF:-v0.7.1}"
POWERLEVEL10K_REF="${POWERLEVEL10K_REF:-v1.20.0}"
DOCKER_CHANNEL="${DOCKER_CHANNEL:-stable}"
DOCKER_CE_VERSION="${DOCKER_CE_VERSION:-}"
DOCKER_RPM_REPO_URL="${DOCKER_RPM_REPO_URL:-}"
DOCKER_RPM_IP_RESOLVE="${DOCKER_RPM_IP_RESOLVE:-4}"
DOCKER_RPM_MAX_PARALLEL_DOWNLOADS="${DOCKER_RPM_MAX_PARALLEL_DOWNLOADS:-1}"
DOCKER_RPM_TIMEOUT="${DOCKER_RPM_TIMEOUT:-120}"
DOCKER_RPM_RETRIES="${DOCKER_RPM_RETRIES:-10}"
DOCKER_REINSTALL="${DOCKER_REINSTALL:-0}"
CURL_RETRY_ARGS=(--retry 3)
readonly SUPERVISOR_UNIT_FILE="/etc/systemd/system/supervisord.service"
readonly SUPERVISOR_CONFIG_MARKER_START="; >>> depends-dev-tools supervisor >>>"
readonly SUPERVISOR_CONFIG_MARKER_END="; <<< depends-dev-tools supervisor <<<"
readonly SUPERVISOR_UNIT_MARKER_START="# >>> depends-dev-tools supervisor >>>"
readonly SUPERVISOR_UNIT_MARKER_END="# <<< depends-dev-tools supervisor <<<"

usage() {
  cat <<'USAGE'
Usage: install-tools.sh [--dry-run] [--help]

Install stable development tools on a supported Linux distribution:
  git, zsh, Oh My Zsh, Node.js/npm, Supervisor, Miniconda, Docker Engine and Docker Compose.

Options:
  --dry-run  Print the commands that would be run without changing the host.
  --help     Show this help text.

Environment overrides:
  TARGET_USER       User that receives Oh My Zsh and Miniconda; defaults to the current user.
  MINICONDA_VERSION Official Miniconda release, default: latest (stable channel).
  MINICONDA_PREFIX  Install location, default: $TARGET_USER's home/miniconda3.
  SUPERVISOR_VERSION Optional exact stable Supervisor release for pip installs.
  SUPERVISOR_CONFIG  Supervisor configuration path, default: /etc/supervisord.conf.
  OH_MY_ZSH_REF     Oh My Zsh branch or tag, default: master.
  OH_MY_ZSH_REPO    Oh My Zsh repository URL.
  ZSH_SYNTAX_HIGHLIGHTING_REF  Plugin tag, default: 0.8.0.
  ZSH_AUTOSUGGESTIONS_REF      Plugin tag, default: v0.7.1.
  POWERLEVEL10K_REF             Theme tag, default: v1.20.0.
  DOCKER_CHANNEL    Docker repository channel; only 'stable' is accepted.
  DOCKER_CE_VERSION Optional exact docker-ce/docker-ce-cli package version on APT.
  DOCKER_RPM_REPO_URL Optional HTTPS Docker RPM repo override for restricted networks.
  DOCKER_RPM_IP_RESOLVE Address family for DNF/YUM downloads: 4, 6, or auto; default: 4.
  DOCKER_RPM_MAX_PARALLEL_DOWNLOADS DNF/YUM package download concurrency; default: 1.
  DOCKER_RPM_TIMEOUT DNF/YUM network timeout in seconds; default: 120.
  DOCKER_RPM_RETRIES DNF/YUM retry count for failed downloads; default: 10.
  DOCKER_REINSTALL    Set to 1 to reinstall Docker even when Engine and Compose exist.

The script supports Debian/Ubuntu (APT), Fedora/RHEL/CentOS (DNF/YUM),
and Arch Linux (Pacman). It sets TARGET_USER's default login shell to zsh.
Log out and back in after Docker group membership is changed.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

show_command() {
  local arg
  printf '[dry-run]'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

root_cmd() {
  if (( DRY_RUN )); then
    show_command "$@"
  elif (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

configure_curl_retry_args() {
  CURL_RETRY_ARGS=(--retry 3)
  if command -v curl >/dev/null 2>&1 && curl --help all 2>/dev/null | grep -Fq -- '--retry-all-errors'; then
    CURL_RETRY_ARGS+=(--retry-all-errors)
  fi
}

user_cmd() {
  if (( DRY_RUN )); then
    show_command "$@"
  elif [[ "$(id -un)" == "$TARGET_USER" ]]; then
    HOME="$TARGET_HOME" "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" -H -- "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$TARGET_USER" -- "$@"
  else
    die "cannot run commands as $TARGET_USER: sudo or runuser is required"
  fi
}

write_root_file() {
  local content="$1"
  local destination="$2"
  if (( DRY_RUN )); then
    log "[dry-run] write generated file $destination"
    return
  fi

  local temporary
  temporary="$(mktemp)"
  printf '%s\n' "$content" >"$temporary"
  root_cmd install -m 0644 "$temporary" "$destination"
  rm -f "$temporary"
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die "this installer only supports Linux"
}

load_os_release() {
  [[ -r /etc/os-release ]] || die "/etc/os-release is missing"
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID,,}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
}

resolve_target_user() {
  [[ -n "$TARGET_USER" ]] || die "TARGET_USER could not be determined"
  id "$TARGET_USER" >/dev/null 2>&1 || die "target user does not exist: $TARGET_USER"
  command -v getent >/dev/null 2>&1 || die "getent is required to resolve the target user's home"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | awk -F: 'NR == 1 { print $6 }')"
  [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "target user's home directory was not found: $TARGET_USER"
  [[ -n "$MINICONDA_PREFIX" ]] || MINICONDA_PREFIX="$TARGET_HOME/miniconda3"
}

require_privileges() {
  if (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
    die "root privileges are required; install sudo or run this script as root with TARGET_USER set"
  fi
}

validate_options() {
  [[ "$DOCKER_CHANNEL" == stable ]] || die "DOCKER_CHANNEL must be stable"
  [[ "$MINICONDA_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die "MINICONDA_VERSION contains unsupported characters"
  if [[ -n "$SUPERVISOR_VERSION" ]]; then
    [[ "$SUPERVISOR_VERSION" =~ ^[0-9][A-Za-z0-9.+_-]*$ ]] ||
      die "SUPERVISOR_VERSION contains unsupported characters"
  fi
  [[ "$SUPERVISOR_CONFIG" = /* ]] || die "SUPERVISOR_CONFIG must be an absolute path"
  [[ "$OH_MY_ZSH_REF" =~ ^[A-Za-z0-9._/@+-]+$ ]] || die "OH_MY_ZSH_REF contains unsupported characters"
  [[ "$ZSH_SYNTAX_HIGHLIGHTING_REF" =~ ^[A-Za-z0-9._/@+-]+$ ]] || die "ZSH_SYNTAX_HIGHLIGHTING_REF contains unsupported characters"
  [[ "$ZSH_AUTOSUGGESTIONS_REF" =~ ^[A-Za-z0-9._/@+-]+$ ]] || die "ZSH_AUTOSUGGESTIONS_REF contains unsupported characters"
  [[ "$POWERLEVEL10K_REF" =~ ^[A-Za-z0-9._/@+-]+$ ]] || die "POWERLEVEL10K_REF contains unsupported characters"
  if [[ -n "$MINICONDA_PREFIX" ]]; then
    [[ "$MINICONDA_PREFIX" = /* ]] || die "MINICONDA_PREFIX must be an absolute path"
  fi
  if [[ -n "$DOCKER_CE_VERSION" ]]; then
    [[ "$DOCKER_CE_VERSION" =~ ^[0-9][A-Za-z0-9.+:~_-]*$ ]] || die "DOCKER_CE_VERSION contains unsupported characters"
  fi
  if [[ -n "$DOCKER_RPM_REPO_URL" ]]; then
    [[ "$DOCKER_RPM_REPO_URL" == https://* ]] || die "DOCKER_RPM_REPO_URL must use HTTPS"
  fi
  [[ "$DOCKER_RPM_IP_RESOLVE" == 4 || "$DOCKER_RPM_IP_RESOLVE" == 6 || "$DOCKER_RPM_IP_RESOLVE" == auto ]] ||
    die "DOCKER_RPM_IP_RESOLVE must be 4, 6, or auto"
  [[ "$DOCKER_RPM_MAX_PARALLEL_DOWNLOADS" =~ ^[1-9][0-9]*$ ]] ||
    die "DOCKER_RPM_MAX_PARALLEL_DOWNLOADS must be a positive integer"
  [[ "$DOCKER_RPM_TIMEOUT" =~ ^[1-9][0-9]*$ ]] ||
    die "DOCKER_RPM_TIMEOUT must be a positive integer"
  [[ "$DOCKER_RPM_RETRIES" =~ ^[1-9][0-9]*$ ]] ||
    die "DOCKER_RPM_RETRIES must be a positive integer"
  [[ "$DOCKER_REINSTALL" == 0 || "$DOCKER_REINSTALL" == 1 ]] ||
    die "DOCKER_REINSTALL must be 0 or 1"
  [[ "$SUPERVISOR_CONFIG" != *[[:space:]]* ]] ||
    die "SUPERVISOR_CONFIG must not contain whitespace"
}

install_docker_apt_repository() {
  local architecture docker_os codename repository
  architecture="$(dpkg --print-architecture)"
  docker_os="$OS_ID"
  codename="$OS_VERSION_CODENAME"
  [[ "$docker_os" == debian || "$docker_os" == ubuntu ]] || die "APT Docker repository is unsupported for $OS_ID"
  [[ -n "$codename" ]] || die "could not determine the $OS_ID release codename"

  root_cmd install -d -m 0755 /etc/apt/keyrings
  if (( DRY_RUN )); then
    log "[dry-run] download Docker's stable signing key to /etc/apt/keyrings/docker.asc"
  else
    curl -fsSL --retry 3 "https://download.docker.com/linux/$docker_os/gpg" |
      root_cmd tee /etc/apt/keyrings/docker.asc >/dev/null
    root_cmd chmod a+r /etc/apt/keyrings/docker.asc
  fi

  repository="deb [arch=$architecture signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$docker_os $codename stable"
  write_root_file "$repository" /etc/apt/sources.list.d/docker.list
}

docker_tools_available() {
  (( DOCKER_REINSTALL == 0 )) || return 1
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  return 0
}

install_apt() {
  local docker_packages
  root_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
  root_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git zsh nodejs npm supervisor
  configure_curl_retry_args

  if docker_tools_available; then
    log 'Docker Engine and Compose already installed; skipping Docker package installation'
    return
  fi

  install_docker_apt_repository
  root_cmd env DEBIAN_FRONTEND=noninteractive apt-get update

  docker_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  if [[ -n "$DOCKER_CE_VERSION" ]]; then
    docker_packages=("docker-ce=$DOCKER_CE_VERSION" "docker-ce-cli=$DOCKER_CE_VERSION" containerd.io docker-buildx-plugin docker-compose-plugin)
  fi
  root_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${docker_packages[@]}"
}

install_dnf_or_yum() {
  local package_manager="$1"
  local docker_repo_url repo_file
  local curl_address_args=()
  local disabled_repo_args=()
  if [[ "$OS_ID" == fedora ]]; then
    docker_repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
  else
    docker_repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
  fi
  [[ -n "$DOCKER_RPM_REPO_URL" ]] && docker_repo_url="$DOCKER_RPM_REPO_URL"
  case "$DOCKER_RPM_IP_RESOLVE" in
    4) curl_address_args=(--ipv4) ;;
    6) curl_address_args=(--ipv6) ;;
    auto) DOCKER_RPM_IP_RESOLVE=whatever ;;
  esac
  if [[ -e /etc/yum.repos.d/docker-ce.repo ]]; then
    disabled_repo_args=(--disablerepo='docker-ce*')
  fi

  if [[ "$package_manager" == dnf ]]; then
    root_cmd dnf \
      "${disabled_repo_args[@]}" \
      --setopt="ip_resolve=$DOCKER_RPM_IP_RESOLVE" \
      --setopt="max_parallel_downloads=$DOCKER_RPM_MAX_PARALLEL_DOWNLOADS" \
      --setopt="timeout=$DOCKER_RPM_TIMEOUT" \
      --setopt="retries=$DOCKER_RPM_RETRIES" \
      --setopt=fastestmirror=False \
      -y install ca-certificates curl git zsh nodejs npm python3-pip
    configure_curl_retry_args
  else
    root_cmd yum \
      "${disabled_repo_args[@]}" \
      --setopt="ip_resolve=$DOCKER_RPM_IP_RESOLVE" \
      --setopt="max_parallel_downloads=$DOCKER_RPM_MAX_PARALLEL_DOWNLOADS" \
      --setopt="timeout=$DOCKER_RPM_TIMEOUT" \
      --setopt="retries=$DOCKER_RPM_RETRIES" \
      --setopt=fastestmirror=False \
      -y install ca-certificates curl git zsh nodejs npm python3-pip
    configure_curl_retry_args
  fi

  if docker_tools_available; then
    log 'Docker Engine and Compose already installed; skipping Docker package installation'
    return
  fi

  repo_file="$(mktemp)"
  if (( DRY_RUN )); then
    log "[dry-run] download Docker RPM repository definition from $docker_repo_url"
  elif ! curl "${curl_address_args[@]}" -fsSL "${CURL_RETRY_ARGS[@]}" --connect-timeout 15 --max-time 60 \
    -o "$repo_file" "$docker_repo_url"; then
    rm -f "$repo_file"
    die "unable to reach Docker repository $docker_repo_url; check DNS/TLS/proxy access or set DOCKER_RPM_REPO_URL to an approved HTTPS mirror"
  fi
  if (( DRY_RUN )); then
    log '[dry-run] install /etc/yum.repos.d/docker-ce.repo'
  else
    root_cmd install -m 0644 "$repo_file" /etc/yum.repos.d/docker-ce.repo
  fi
  rm -f "$repo_file"
  root_cmd "$package_manager" \
    --setopt="ip_resolve=$DOCKER_RPM_IP_RESOLVE" \
    --setopt="max_parallel_downloads=$DOCKER_RPM_MAX_PARALLEL_DOWNLOADS" \
    --setopt="timeout=$DOCKER_RPM_TIMEOUT" \
    --setopt="retries=$DOCKER_RPM_RETRIES" \
    --setopt=fastestmirror=False \
    -y install \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_pacman() {
  root_cmd pacman --noconfirm --needed -Sy \
    ca-certificates curl git zsh nodejs npm supervisor
  configure_curl_retry_args
  if docker_tools_available; then
    log 'Docker Engine and Compose already installed; skipping Docker package installation'
    return
  fi
  root_cmd pacman --noconfirm --needed -S docker docker-compose
}

install_system_packages() {
  case "$OS_ID" in
    debian|ubuntu)
      install_apt
      ;;
    fedora|rhel|centos|rocky|almalinux)
      if command -v dnf >/dev/null 2>&1; then
        install_dnf_or_yum dnf
      elif command -v yum >/dev/null 2>&1; then
        install_dnf_or_yum yum
      else
        die "neither dnf nor yum is available on $OS_ID"
      fi
      ;;
    arch|manjaro)
      command -v pacman >/dev/null 2>&1 || die "pacman is required on $OS_ID"
      install_pacman
      ;;
    *)
      die "unsupported Linux distribution: $OS_ID (supported: Debian, Ubuntu, Fedora, RHEL/CentOS, Arch)"
      ;;
  esac
}

supervisor_available() {
  command -v supervisord >/dev/null 2>&1 && command -v supervisorctl >/dev/null 2>&1
}

install_supervisor_pip() {
  local package_spec="supervisor"
  local pip_args=()
  [[ -n "$SUPERVISOR_VERSION" ]] && package_spec="supervisor==$SUPERVISOR_VERSION"

  if supervisor_available; then
    log 'Supervisor is already installed; leaving it unchanged'
    return
  fi
  if (( DRY_RUN )); then
    root_cmd python3 -m pip install --upgrade "$package_spec"
    return
  fi
  command -v python3 >/dev/null 2>&1 || die 'python3 is required to install Supervisor on RPM-based systems'
  python3 -m pip --version >/dev/null 2>&1 || die 'python3-pip is required to install Supervisor on RPM-based systems'
  if python3 -m pip install --help 2>&1 | grep -Fq -- '--break-system-packages'; then
    pip_args+=(--break-system-packages)
  fi
  root_cmd python3 -m pip install --upgrade "${pip_args[@]}" "$package_spec"
}

install_supervisor() {
  case "$OS_ID" in
    fedora|rhel|centos|rocky|almalinux)
      install_supervisor_pip
      ;;
  esac
}

configure_supervisor() {
  local config_directory supervisord_path supervisorctl_path config_content unit_content
  config_directory="$(dirname "$SUPERVISOR_CONFIG")"
  root_cmd install -d -m 0755 "$config_directory" /etc/supervisord.d /var/log/supervisor

  if (( DRY_RUN )); then
    log "[dry-run] generate Supervisor configuration at $SUPERVISOR_CONFIG when it is absent"
  elif [[ -L "$SUPERVISOR_CONFIG" ]]; then
    die "refusing symlink Supervisor configuration: $SUPERVISOR_CONFIG"
  elif [[ -e "$SUPERVISOR_CONFIG" && ! -f "$SUPERVISOR_CONFIG" ]]; then
    die "Supervisor configuration is not a regular file: $SUPERVISOR_CONFIG"
  elif [[ ! -e "$SUPERVISOR_CONFIG" ]]; then
    config_content=$(cat <<CONFIG
; Managed by scripts/install-tools.sh.
$SUPERVISOR_CONFIG_MARKER_START
[unix_http_server]
file=/run/supervisor/supervisor.sock
chmod=0700

[inet_http_server]
port=127.0.0.1:9001

[supervisord]
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
pidfile=/run/supervisor/supervisord.pid
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=http://127.0.0.1:9001

[include]
files = /etc/supervisord.d/*.ini
$SUPERVISOR_CONFIG_MARKER_END
CONFIG
)
    write_root_file "$config_content" "$SUPERVISOR_CONFIG"
    log "generated Supervisor configuration at $SUPERVISOR_CONFIG"
  else
    log "Supervisor configuration already exists at $SUPERVISOR_CONFIG; leaving it unchanged"
  fi

  supervisord_path="$(command -v supervisord 2>/dev/null || printf '/usr/local/bin/supervisord')"
  supervisorctl_path="$(command -v supervisorctl 2>/dev/null || printf '/usr/local/bin/supervisorctl')"
  if (( ! DRY_RUN )); then
    [[ -x "$supervisord_path" ]] || die "supervisord was not found at $supervisord_path"
    [[ -x "$supervisorctl_path" ]] || die "supervisorctl was not found at $supervisorctl_path"
  fi

  if (( DRY_RUN )); then
    log "[dry-run] generate systemd unit $SUPERVISOR_UNIT_FILE when absent"
  elif [[ -L "$SUPERVISOR_UNIT_FILE" ]]; then
    die "refusing symlink Supervisor systemd unit: $SUPERVISOR_UNIT_FILE"
  elif [[ -e "$SUPERVISOR_UNIT_FILE" && ! -f "$SUPERVISOR_UNIT_FILE" ]]; then
    die "Supervisor systemd unit is not a regular file: $SUPERVISOR_UNIT_FILE"
  elif [[ ! -e "$SUPERVISOR_UNIT_FILE" ]] || grep -Fq "$SUPERVISOR_UNIT_MARKER_START" "$SUPERVISOR_UNIT_FILE"; then
    unit_content=$(cat <<UNIT
[Unit]
Description=Supervisor process control system
Documentation=https://supervisord.org
After=network.target

[Service]
Type=forking
PIDFile=/run/supervisor/supervisord.pid
RuntimeDirectory=supervisor
RuntimeDirectoryMode=0755
ExecStart=$supervisord_path -c $SUPERVISOR_CONFIG
ExecStop=$supervisorctl_path -c $SUPERVISOR_CONFIG shutdown
ExecReload=$supervisorctl_path -c $SUPERVISOR_CONFIG reload
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target

$SUPERVISOR_UNIT_MARKER_START
$SUPERVISOR_UNIT_MARKER_END
UNIT
)
    write_root_file "$unit_content" "$SUPERVISOR_UNIT_FILE"
    log "generated systemd unit $SUPERVISOR_UNIT_FILE"
  else
    log "Supervisor systemd unit already exists at $SUPERVISOR_UNIT_FILE; leaving it unchanged"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    root_cmd systemctl daemon-reload
    root_cmd systemctl enable --now supervisord.service
  else
    log 'warning: systemctl is unavailable; start supervisord with the host service manager'
  fi
}

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null || printf '/usr/bin/zsh')"
  if (( ! DRY_RUN )) && [[ ! -x "$zsh_path" ]]; then
    die "zsh was not found after package installation"
  fi
  if (( DRY_RUN )); then
    log "[dry-run] ensure $zsh_path is listed in /etc/shells"
  elif ! grep -Fxq "$zsh_path" /etc/shells; then
    printf '%s\n' "$zsh_path" | root_cmd tee -a /etc/shells >/dev/null
  fi
  root_cmd usermod --shell "$zsh_path" "$TARGET_USER"
  log "set $TARGET_USER's default login shell to $zsh_path"
}

enable_docker() {
  if command -v systemctl >/dev/null 2>&1; then
    root_cmd systemctl enable --now docker
  else
    log "warning: systemctl is unavailable; start Docker with the host's service manager"
  fi

  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    return
  fi
  root_cmd usermod -aG docker "$TARGET_USER"
  log "added $TARGET_USER to the docker group; log out and back in before using Docker without sudo"
}

clone_user_repo() {
  local repository="$1"
  local ref="$2"
  local destination="$3"

  if [[ -d "$destination" ]]; then
    log "Repository already exists at $destination; leaving it unchanged"
  else
    user_cmd git clone --depth 1 --single-branch --branch "$ref" "$repository" "$destination"
  fi
}

ensure_zshrc_block() {
  local zshrc="$TARGET_HOME/.zshrc"
  local marker='# >>> depends-dev-tools >>>'
  local fragment
  local block

  block=$(cat <<'ZSH_BLOCK'

# >>> depends-dev-tools >>>
# Managed by scripts/install-tools.sh. Keep this block intact for idempotent updates.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
[[ -r "$ZSH/custom/themes/powerlevel10k/powerlevel10k.zsh-theme" ]] && source "$ZSH/custom/themes/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -r "$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -r "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
# <<< depends-dev-tools <<<
ZSH_BLOCK
  )

  if (( DRY_RUN )); then
    log "[dry-run] append managed Oh My Zsh configuration to $zshrc"
    return
  fi
  if [[ -f "$zshrc" ]] && grep -Fq "$marker" "$zshrc"; then
    log "managed Oh My Zsh configuration already exists in $zshrc"
    return
  fi

  fragment="$(mktemp)"
  printf '%s\n' "$block" >"$fragment"
  chmod 0644 "$fragment"
  if [[ ! -e "$zshrc" ]]; then
    user_cmd install -m 0644 "$fragment" "$zshrc"
  else
    user_cmd sh -c 'cat "$1" >> "$2"' _ "$fragment" "$zshrc"
  fi
  rm -f "$fragment"
}

install_oh_my_zsh() {
  local zsh_dir="$TARGET_HOME/.oh-my-zsh"
  local custom_dir="$zsh_dir/custom"
  local p10k_config

  if [[ -d "$zsh_dir" ]]; then
    log "Oh My Zsh already exists at $zsh_dir; leaving it unchanged"
  else
    clone_user_repo "$OH_MY_ZSH_REPO" "$OH_MY_ZSH_REF" "$zsh_dir"
  fi

  user_cmd mkdir -p "$custom_dir/plugins" "$custom_dir/themes"
  clone_user_repo \
    "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
    "$ZSH_SYNTAX_HIGHLIGHTING_REF" \
    "$custom_dir/plugins/zsh-syntax-highlighting"
  clone_user_repo \
    "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$ZSH_AUTOSUGGESTIONS_REF" \
    "$custom_dir/plugins/zsh-autosuggestions"
  clone_user_repo \
    "https://github.com/romkatv/powerlevel10k.git" \
    "$POWERLEVEL10K_REF" \
    "$custom_dir/themes/powerlevel10k"

  if [[ ! -e "$TARGET_HOME/.zshrc" ]]; then
    user_cmd cp "$zsh_dir/templates/zshrc.zsh-template" "$TARGET_HOME/.zshrc"
  fi

  p10k_config="$custom_dir/themes/powerlevel10k/config/p10k-lean.zsh"
  if [[ -e "$TARGET_HOME/.p10k.zsh" ]]; then
    log "$TARGET_HOME/.p10k.zsh already exists; leaving it unchanged"
  else
    user_cmd cp "$p10k_config" "$TARGET_HOME/.p10k.zsh"
  fi
  ensure_zshrc_block
}

miniconda_architecture() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64\n' ;;
    aarch64|arm64) printf 'aarch64\n' ;;
    *) die "unsupported Linux architecture for Miniconda: $(uname -m)" ;;
  esac
}

install_miniconda() {
  local architecture installer_name installer_url checksum_url installer checksum expected actual cleanup_trap
  architecture="$(miniconda_architecture)"
  # With the default channel this resolves to Miniconda3-latest-Linux-<architecture>.sh.
  installer_name="Miniconda3-$MINICONDA_VERSION-Linux-$architecture.sh"
  installer_url="$MINICONDA_BASE_URL/$installer_name"
  # Anaconda publishes SHA-256 values in the directory index rather than .sha256 sidecars.
  checksum_url="$MINICONDA_BASE_URL/"

  if [[ -x "$MINICONDA_PREFIX/bin/conda" ]]; then
    log "Miniconda already exists at $MINICONDA_PREFIX; leaving it unchanged"
    return
  fi
  [[ ! -e "$MINICONDA_PREFIX" ]] || die "Miniconda target exists but is incomplete: $MINICONDA_PREFIX"

  if (( DRY_RUN )); then
    log "[dry-run] download and verify $installer_url"
    log "[dry-run] install Miniconda into $MINICONDA_PREFIX for $TARGET_USER"
    return
  fi

  installer="$(mktemp --suffix=.sh)"
  checksum="$(mktemp)"
  cleanup_trap="rm -f $(printf '%q' "$installer") $(printf '%q' "$checksum")"
  trap "$cleanup_trap" EXIT
  if ! curl -fsSL "${CURL_RETRY_ARGS[@]}" -o "$installer" "$installer_url"; then
    rm -f "$installer" "$checksum"
    die "failed to download Miniconda installer (installer_url=$installer_url)"
  fi
  if ! curl -fsSL "${CURL_RETRY_ARGS[@]}" -o "$checksum" "$checksum_url"; then
    rm -f "$installer" "$checksum"
    die "failed to download Miniconda checksum index (checksum_url=$checksum_url)"
  fi
  expected="$(awk -v installer_name="$installer_name" '
    index($0, "href=\"" installer_name "\"") { in_entry=1; next }
    in_entry {
      if (match($0, /[[:xdigit:]]{64}/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
      if (index($0, "</tr>")) in_entry=0
    }
  ' "$checksum")"
  actual="$(sha256sum "$installer" | awk '{ print $1 }')"
  [[ -n "$expected" ]] || die "Miniconda checksum was not found in index (installer_url=$installer_url, checksum_url=$checksum_url)"
  [[ "$expected" == "$actual" ]] || die "Miniconda checksum verification failed"

  root_cmd chown "$TARGET_USER:" "$installer" "$checksum"
  user_cmd bash "$installer" -b -p "$MINICONDA_PREFIX"
  user_cmd "$MINICONDA_PREFIX/bin/conda" init bash zsh
  rm -f "$installer" "$checksum"
  trap - EXIT
}

verify_installation() {
  if (( DRY_RUN )); then
    log '[dry-run] skip command verification'
    return
  fi

  command -v git >/dev/null 2>&1 || die 'git was not installed'
  command -v zsh >/dev/null 2>&1 || die 'zsh was not installed'
  command -v node >/dev/null 2>&1 || die 'Node.js was not installed'
  command -v npm >/dev/null 2>&1 || die 'npm was not installed'
  command -v supervisord >/dev/null 2>&1 || die 'Supervisor was not installed'
  command -v supervisorctl >/dev/null 2>&1 || die 'supervisorctl is not available'
  supervisorctl -c "$SUPERVISOR_CONFIG" status >/dev/null ||
    die "Supervisor is not responding with configuration $SUPERVISOR_CONFIG"
  command -v docker >/dev/null 2>&1 || die 'docker was not installed'
  docker compose version >/dev/null 2>&1 || die 'docker compose is not available'
  [[ -x "$MINICONDA_PREFIX/bin/conda" ]] || die "Miniconda was not installed at $MINICONDA_PREFIX"

  log 'Installed tool versions:'
  git --version
  zsh --version | head -n 1
  node --version
  npm --version
  supervisord --version
  docker --version
  docker compose version
  "$MINICONDA_PREFIX/bin/conda" --version
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --help|-h) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux
  load_os_release
  resolve_target_user
  validate_options
  require_privileges

  log "Installing stable development tools for $TARGET_USER on $OS_ID"
  install_system_packages
  install_supervisor
  configure_supervisor
  set_default_shell
  enable_docker
  install_oh_my_zsh
  install_miniconda
  verify_installation
  log 'Installation complete.'
}

main "$@"
