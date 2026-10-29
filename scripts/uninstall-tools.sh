#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

DRY_RUN=0
ASSUME_YES=0
PURGE_USER_CONFIG=0
PURGE_DOCKER_DATA=0
REMOVE_DOCKER_REPO=0
TARGET_USER="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"
MINICONDA_PREFIX="${MINICONDA_PREFIX:-}"
SUPERVISOR_CONFIG="${SUPERVISOR_CONFIG:-/etc/supervisord.conf}"
readonly SUPERVISOR_UNIT_FILE="/etc/systemd/system/supervisord.service"
readonly SUPERVISOR_CONFIG_MARKER_START="; >>> depends-dev-tools supervisor >>>"
readonly SUPERVISOR_UNIT_MARKER_START="# >>> depends-dev-tools supervisor >>>"

usage() {
  cat <<'USAGE'
Usage: uninstall-tools.sh [options]

Remove tools installed by scripts/install-tools.sh:
  Git, zsh, Node.js/npm, Supervisor, Docker Engine/Compose, Miniconda and managed shell setup.

Options:
  --dry-run             Print actions without changing the host.
  --yes                 Skip the confirmation prompt.
  --purge-user-config   Also remove TARGET_USER's .oh-my-zsh and .p10k.zsh.
  --purge-docker-data   Also delete /var/lib/docker and /var/lib/containerd.
  --remove-docker-repo  Remove the Docker repository definition and signing key.
  --help                Show this help text.

Environment overrides:
  TARGET_USER       User whose shell setup and Miniconda are removed; default: current user.
  MINICONDA_PREFIX  Miniconda path; default: TARGET_USER's home/miniconda3.
  SUPERVISOR_CONFIG Supervisor configuration path; default: /etc/supervisord.conf.

The script preserves Docker data, Docker repository files, .oh-my-zsh and .p10k.zsh
unless their explicit options are selected. It never removes Compose project data.
If zsh is the target user's login shell, the script changes it to bash after
confirmation and before removing zsh.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

root_cmd() {
  if (( DRY_RUN )); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  elif (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die 'root privileges are required; run this script as root or install sudo'
  fi
}

user_cmd() {
  if (( DRY_RUN )); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
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

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'this script only supports Linux'
}

load_os_release() {
  [[ -r /etc/os-release ]] || die '/etc/os-release is missing'
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID,,}"
}

resolve_target_user() {
  [[ -n "$TARGET_USER" ]] || die 'TARGET_USER could not be determined'
  id "$TARGET_USER" >/dev/null 2>&1 || die "target user does not exist: $TARGET_USER"
  command -v getent >/dev/null 2>&1 || die 'getent is required to resolve the target home'
  TARGET_HOME="$(getent passwd "$TARGET_USER" | awk -F: 'NR == 1 { print $6 }')"
  [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "target home was not found: $TARGET_USER"
  [[ -n "$MINICONDA_PREFIX" ]] || MINICONDA_PREFIX="$TARGET_HOME/miniconda3"
}

validate_paths() {
  [[ "$MINICONDA_PREFIX" = /* ]] || die 'MINICONDA_PREFIX must be an absolute path'
  [[ "$MINICONDA_PREFIX" != / && "$MINICONDA_PREFIX" != "$TARGET_HOME" ]] ||
    die "refusing unsafe Miniconda path: $MINICONDA_PREFIX"
  [[ "$MINICONDA_PREFIX" != */.. && "$MINICONDA_PREFIX" != */../* ]] ||
    die "MINICONDA_PREFIX must not contain '..': $MINICONDA_PREFIX"
  [[ "$SUPERVISOR_CONFIG" = /* ]] || die 'SUPERVISOR_CONFIG must be an absolute path'
  [[ "$SUPERVISOR_CONFIG" != *[[:space:]]* ]] || die 'SUPERVISOR_CONFIG must not contain whitespace'
  [[ ! -L "$MINICONDA_PREFIX" ]] || die "refusing symlink Miniconda path: $MINICONDA_PREFIX"
  if [[ -e "$MINICONDA_PREFIX" && ! -d "$MINICONDA_PREFIX" ]]; then
    die "Miniconda path is not a directory: $MINICONDA_PREFIX"
  fi
}

check_login_shell() {
  TARGET_LOGIN_SHELL="$(getent passwd "$TARGET_USER" | awk -F: 'NR == 1 { print $7 }')"
}

reset_login_shell_if_needed() {
  local bash_path
  if [[ "$TARGET_LOGIN_SHELL" != */zsh ]]; then
    return 0
  fi
  bash_path="$(command -v bash 2>/dev/null || printf '/bin/bash')"
  [[ -x "$bash_path" ]] || die "bash was not found; cannot safely remove zsh"
  root_cmd usermod --shell "$bash_path" "$TARGET_USER"
  log "changed $TARGET_USER's login shell from $TARGET_LOGIN_SHELL to $bash_path"
}

remove_marked_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  local temporary

  [[ -f "$file" ]] || return 0
  if ! grep -Fq "$start" "$file"; then
    return 0
  fi
  grep -Fq "$end" "$file" || die "unclosed managed block in $file; refusing to edit it"
  if (( DRY_RUN )); then
    log "[dry-run] remove managed block from $file"
    return 0
  fi

  temporary="$(mktemp)"
  user_cmd awk -v start="$start" -v end="$end" '
    index($0, start) { skipping=1; next }
    skipping && index($0, end) { skipping=0; next }
    !skipping { print }
  ' "$file" >"$temporary"
  root_cmd cp "$temporary" "$file"
  rm -f "$temporary"
}

remove_user_shell_setup() {
  remove_marked_block "$TARGET_HOME/.zshrc" \
    '# >>> depends-dev-tools >>>' '# <<< depends-dev-tools <<<'
  remove_marked_block "$TARGET_HOME/.bashrc" \
    '# >>> conda initialize >>>' '# <<< conda initialize <<<'
  remove_marked_block "$TARGET_HOME/.zshrc" \
    '# >>> conda initialize >>>' '# <<< conda initialize <<<'

  if (( PURGE_USER_CONFIG )); then
    for path in "$TARGET_HOME/.oh-my-zsh" "$TARGET_HOME/.p10k.zsh"; do
      [[ ! -L "$path" ]] || die "refusing symlink user config path: $path"
      if [[ -e "$path" ]]; then
        root_cmd rm -rf -- "$path"
      fi
    done
  fi
}

remove_miniconda() {
  if [[ -e "$MINICONDA_PREFIX" ]]; then
    root_cmd rm -rf -- "$MINICONDA_PREFIX"
    log "removed Miniconda at $MINICONDA_PREFIX"
  else
    log "Miniconda not found at $MINICONDA_PREFIX"
  fi
}

remove_supervisor_pip() {
  local pip_args=()
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -m pip show supervisor >/dev/null 2>&1 || return 0
  if python3 -m pip uninstall --help 2>&1 | grep -Fq -- '--break-system-packages'; then
    pip_args+=(--break-system-packages)
  fi
  root_cmd python3 -m pip uninstall -y "${pip_args[@]}" supervisor
}

remove_supervisor_service() {
  local unit removed=0
  if command -v systemctl >/dev/null 2>&1; then
    for unit in supervisord.service supervisor.service; do
      if (( DRY_RUN )); then
        root_cmd systemctl disable --now "$unit"
      elif systemctl is-active --quiet "$unit" || systemctl is-enabled --quiet "$unit"; then
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
      fi
    done
  fi

  [[ ! -L "$SUPERVISOR_UNIT_FILE" ]] || die "refusing symlink Supervisor systemd unit: $SUPERVISOR_UNIT_FILE"
  if [[ -f "$SUPERVISOR_UNIT_FILE" ]] && grep -Fq "$SUPERVISOR_UNIT_MARKER_START" "$SUPERVISOR_UNIT_FILE"; then
    root_cmd rm -f -- "$SUPERVISOR_UNIT_FILE"
    removed=1
  fi
  if (( removed )) && command -v systemctl >/dev/null 2>&1; then
    root_cmd systemctl daemon-reload
  fi

  [[ ! -L "$SUPERVISOR_CONFIG" ]] || die "refusing symlink Supervisor configuration: $SUPERVISOR_CONFIG"
  if [[ -f "$SUPERVISOR_CONFIG" ]] && grep -Fq "$SUPERVISOR_CONFIG_MARKER_START" "$SUPERVISOR_CONFIG"; then
    root_cmd rm -f -- "$SUPERVISOR_CONFIG"
    log "removed script-managed Supervisor configuration at $SUPERVISOR_CONFIG"
  fi
}

stop_docker() {
  command -v systemctl >/dev/null 2>&1 || return 0
  local unit
  for unit in docker.service docker.socket containerd.service; do
    if (( DRY_RUN )); then
      root_cmd systemctl disable --now "$unit"
    else
      systemctl disable --now "$unit" >/dev/null 2>&1 || true
    fi
  done
}

docker_packages_dnf=()
docker_packages_apt=()
docker_packages_arch=()

collect_installed_packages() {
  local package
  case "$OS_ID" in
    debian|ubuntu)
      for package in git zsh nodejs npm supervisor docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fq 'install ok installed'; then
          docker_packages_apt+=("$package")
        fi
      done
      ;;
    fedora|rhel|centos|rocky|almalinux)
      for package in git zsh nodejs nodejs-npm supervisor docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do
        if rpm -q "$package" >/dev/null 2>&1; then
          docker_packages_dnf+=("$package")
        fi
      done
      ;;
    arch|manjaro)
      for package in git zsh nodejs npm supervisor docker docker-compose; do
        if pacman -Qq "$package" >/dev/null 2>&1; then
          docker_packages_arch+=("$package")
        fi
      done
      ;;
    *)
      die "unsupported Linux distribution: $OS_ID"
      ;;
  esac
}

remove_system_packages() {
  if ((${#docker_packages_apt[@]})); then
    root_cmd env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${docker_packages_apt[@]}"
  fi
  if ((${#docker_packages_dnf[@]})); then
    root_cmd dnf --disablerepo='*' -y remove "${docker_packages_dnf[@]}"
  fi
  if ((${#docker_packages_arch[@]})); then
    root_cmd pacman --noconfirm -R "${docker_packages_arch[@]}"
  fi
}

remove_docker_repo() {
  (( REMOVE_DOCKER_REPO )) || return 0
  for path in /etc/yum.repos.d/docker-ce.repo /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc; do
    [[ ! -L "$path" ]] || die "refusing symlink Docker repository path: $path"
    if [[ -e "$path" ]]; then
      root_cmd rm -f -- "$path"
    fi
  done
}

remove_docker_data() {
  (( PURGE_DOCKER_DATA )) || return 0
  for path in /var/lib/docker /var/lib/containerd; do
    [[ ! -L "$path" ]] || die "refusing symlink Docker data path: $path"
    if [[ -e "$path" ]]; then
      root_cmd rm -rf -- "$path"
    fi
  done
}

print_plan() {
  log "Target user: $TARGET_USER ($TARGET_HOME)"
  log "Miniconda path: $MINICONDA_PREFIX"
  log 'Will remove installed Git, zsh, Node.js/npm, Docker Engine/Compose packages, Miniconda, and managed shell blocks.'
  if (( PURGE_USER_CONFIG )); then
    log 'Will also remove .oh-my-zsh and .p10k.zsh.'
  else
    log 'Will preserve .oh-my-zsh and .p10k.zsh (use --purge-user-config to remove them).'
  fi
  if (( PURGE_DOCKER_DATA )); then
    log 'WILL PERMANENTLY DELETE /var/lib/docker and /var/lib/containerd.'
  else
    log 'Will preserve Docker images, containers, volumes, and build cache.'
  fi
  if (( REMOVE_DOCKER_REPO )); then
    log 'Will remove Docker repository definitions and signing key.'
  fi
  log "Will stop supervisord and remove only script-managed Supervisor configuration at $SUPERVISOR_CONFIG."
  if [[ "$TARGET_LOGIN_SHELL" == */zsh ]]; then
    log "Will change $TARGET_USER's login shell to /bin/bash before removing zsh."
  fi
}

confirm() {
  (( DRY_RUN || ASSUME_YES )) && return 0
  printf 'Type REMOVE DEV TOOLS to continue: '
  local confirmation
  read -r confirmation
  [[ "$confirmation" == 'REMOVE DEV TOOLS' ]] || die 'operation cancelled'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      --purge-user-config) PURGE_USER_CONFIG=1 ;;
      --purge-docker-data) PURGE_DOCKER_DATA=1 ;;
      --remove-docker-repo) REMOVE_DOCKER_REPO=1 ;;
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
  validate_paths
  check_login_shell
  collect_installed_packages
  print_plan
  confirm

  reset_login_shell_if_needed
  remove_supervisor_service
  stop_docker
  remove_docker_data
  remove_user_shell_setup
  remove_miniconda
  remove_supervisor_pip
  remove_system_packages
  remove_docker_repo
  log 'Uninstall complete. Log out and back in to refresh shell and group state.'
}

main "$@"
