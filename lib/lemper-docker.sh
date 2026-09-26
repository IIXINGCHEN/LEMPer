#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Docker & App Market Plugin                                 |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | version 3 (GPLv3).                                                      |
# +-------------------------------------------------------------------------+

if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

# Defensive fallback helpers in case this file is sourced outside the full
# lemper-cli.sh context (which already defines run/info/warning/error).
if [[ "$(type -t info)" != "function" ]]; then
    function info() { echo "Info: $*" >&2; }
fi
if [[ "$(type -t warning)" != "function" ]]; then
    function warning() { echo "Warning: $*" >&2; }
fi
if [[ "$(type -t error)" != "function" ]]; then
    function error() { echo "Error: $*" >&2; }
fi
if [[ "$(type -t success)" != "function" ]]; then
    function success() { echo "Success: $*" >&2; }
fi
if [[ "$(type -t run)" != "function" ]]; then
    function run() { "$@"; }
fi

# App templates installed by install_tools.sh; data lives under /home/docker.
DOCKER_APPS_DIR="/usr/share/lemper/docker/apps"
DOCKER_DATA_BASE="/home/docker"

CMD_NAME="docker"

##
# Print usage for the 'docker' command.
##
function docker_usage() {
    cat <<- EOL
Usage: ${PROG_NAME:-lemper-cli} ${CMD_NAME} <subcommand> [options]

Thin Docker wrapper + curated app market (complements, not replaces,
the LEMPer stack — LEMPer nginx keeps ports 80/443).

Subcommands:
  list                List available apps in the market
  install <app>       Deploy an app (uptime-kuma | vaultwarden)
  uninstall <app>     Stop and remove an app (keeps data unless --purge)
  ps                  Show running Docker containers
  logs <app>          Tail an app's container logs
EOL
}

function docker_require_engine() {
    if ! command -v docker &>/dev/null; then
        error "Docker Engine is not installed. Re-run install.sh with INSTALL_DOCKER=true."
        return 1
    fi
    if ! docker info &>/dev/null; then
        error "Docker daemon is not running."
        return 1
    fi
}

function docker_app_dir() {
    local app="$1"
    [[ -d "${DOCKER_APPS_DIR}/${app}" ]] || { error "Unknown app '${app}'. Run '${CMD_NAME} list'."; return 1; }
    printf '%s' "${DOCKER_APPS_DIR}/${app}"
}

function docker_list() {
    echo "Available apps:"
    local d
    for d in "${DOCKER_APPS_DIR}"/*/; do
        [[ -d "${d}" ]] || continue
        local app
        app=$(basename "${d}")
        local desc=""
        [[ -f "${d}/README.md" ]] && desc=$(head -3 "${d}/README.md" | tail -1)
        printf '  %-16s %s\n' "${app}" "${desc}"
    done
}

function docker_install() {
    local app="${1:-}"
    [[ -n "${app}" ]] || { error "Usage: ${CMD_NAME} install <app>"; return 1; }
    docker_require_engine || return 1
    local src
    src=$(docker_app_dir "${app}") || return 1

    local dest="${DOCKER_DATA_BASE}/${app}"
    run mkdir -p "${dest}"

    # Refresh the compose file from the template.
    run cp -f "${src}/docker-compose.yml" "${dest}/docker-compose.yml"

    # Create .env from the example on first install; generate secrets.
    # The token is written only to ${dest}/.env (mode 600) and never printed.
    if [[ ! -f "${dest}/.env" && -f "${src}/.env.example" ]]; then
        run cp -f "${src}/.env.example" "${dest}/.env"
        run chmod 600 "${dest}/.env"
        if grep -q "^ADMIN_TOKEN=$" "${dest}/.env" 2>/dev/null; then
            local token
            token=$(openssl rand -base64 48 2>/dev/null | tr -d '\n')
            # Fixed-string rewrite: no sed replacement interpolation of the token.
            grep -vE '^ADMIN_TOKEN=' "${dest}/.env" > "${dest}/.env.new" && \
            printf 'ADMIN_TOKEN=%s
' "${token}" >> "${dest}/.env.new" && \
            run mv -f "${dest}/.env.new" "${dest}/.env" && run chmod 600 "${dest}/.env"
            success "Generated ADMIN_TOKEN for ${app}."
            info "Saved in ${dest}/.env (mode 600) — copy it to your password manager now."
            info "Retrieve later with: sudo grep ^ADMIN_TOKEN= ${dest}/.env"
        fi
    fi

    ( cd "${dest}" && run docker compose up -d )
    success "'${app}' deployed. See ${src}/README.md for access details."
}

function docker_uninstall() {
    local app="${1:-}" purge="${2:-}"
    [[ -n "${app}" ]] || { error "Usage: ${CMD_NAME} uninstall <app> [--purge]"; return 1; }
    docker_require_engine || return 1

    local dest="${DOCKER_DATA_BASE}/${app}"
    [[ -f "${dest}/docker-compose.yml" ]] || { error "'${app}' is not installed."; return 1; }

    ( cd "${dest}" && run docker compose down )
    if [[ "${purge}" == "--purge" ]]; then
        warning "Removing all data in ${dest} ..."
        run rm -rf "${dest}"
    else
        info "Data kept in ${dest} (use --purge to wipe it)."
    fi
    success "'${app}' removed."
}

function docker_ps() {
    docker_require_engine || return 1
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

function docker_logs() {
    local app="${1:-}"
    [[ -n "${app}" ]] || { error "Usage: ${CMD_NAME} logs <app>"; return 1; }
    docker_require_engine || return 1

    local dest="${DOCKER_DATA_BASE}/${app}"
    [[ -f "${dest}/docker-compose.yml" ]] || { error "'${app}' is not installed."; return 1; }

    ( cd "${dest}" && docker compose logs --tail=100 -f )
}

# Dispatch subcommand.
DOCKER_SUBCMD="${1:-}"
case "${DOCKER_SUBCMD}" in
    list)      docker_list ;;
    install)   shift; docker_install "$@" ;;
    uninstall) shift; docker_uninstall "$@" ;;
    ps)        docker_ps ;;
    logs)      shift; docker_logs "$@" ;;
    -h|--help|help|"") docker_usage ;;
    *)         error "Unknown subcommand '${DOCKER_SUBCMD}'."; docker_usage; exit 1 ;;
esac
