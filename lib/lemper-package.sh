#!/usr/bin/env bash
# shellcheck disable=SC2317  # plugin lib: subcommands are dispatched dynamically
# ("pkg_subcmd_${CMD}") and invoked indirectly via bin/lemper-cli.sh

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Hosting Package Manager                                    |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+
#
# Hosting package management for the LEMPer CLI.
#
# This is a sourced library plugin, not an executable: it must be sourced
# from bin/lemper-cli.sh (or the 'package' plugin entry point installed at
# /etc/lemper/cli-plugins/lemper-package). Direct execution is refused.
#
# Subcommands (invoked as: lemper-cli package <subcommand> [options]):
#   create <name> --quota <MB> --sites <n> --dbs <n> [--bandwidth <GB>]
#   list
#   delete <name>
#   assign <user> <package>
#   info <user>
#
# On-disk layout (target-system absolute paths):
#   /etc/lemper/packages/<name>.conf          Package definition.
#   /etc/lemper/packages/assigned/<user>      Package assignment record.

#CMD_PARENT="${PROG_NAME}"
CMD_NAME="package"

# Make sure only root can access and not direct access.
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
# 'warn' is a convenient alias; scripts/utils.sh and lemper-cli.sh spell it 'warning'.
if [[ "$(type -t warn)" != "function" ]]; then
    function warn() { warning "$@"; }
fi
if [[ "$(type -t run)" != "function" ]]; then
    function run() { "$@"; }
fi

# Package store locations.
PACKAGES_DIR="/etc/lemper/packages"
ASSIGNED_DIR="/etc/lemper/packages/assigned"

##
# Print usage for the 'package' command.
##
function pkg_usage() {
    cat <<- EOL
Usage: ${PROG_NAME:-lemper-cli} ${CMD_NAME} <subcommand> [options]

Hosting package management.

Subcommands:
  create <name> --quota <MB> --sites <n> --dbs <n> [--bandwidth <GB>]
      Create a new hosting package.
  list
      List all defined hosting packages.
  delete <name>
      Delete a hosting package (cleans up stale assignments).
  assign <user> <package>
      Assign a package to a system user and apply its disk quota.
  info <user>
      Show the package currently assigned to a user.

Package fields:
  DISK_QUOTA_MB   Disk quota in megabytes (positive integer).
  MAX_SITES       Maximum number of virtual hosts (non-negative integer).
  MAX_DATABASES   Maximum number of databases (non-negative integer).
  BANDWIDTH_GB    Monthly bandwidth in gigabytes, bookkeeping only
                  (non-negative integer, 0 = unlimited).
EOL
}

##
# Validate a package name (letters, digits, dash, underscore).
##
function pkg_validate_name() {
    local NAME="${1}"
    if [[ ! "${NAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid package name '${NAME}'. Use only letters, digits, '-' and '_'."
        return 1
    fi
    return 0
}

function pkg_is_positive_int() {
    [[ "${1}" =~ ^[1-9][0-9]*$ ]]
}

function pkg_is_nonneg_int() {
    [[ "${1}" =~ ^[0-9]+$ ]]
}

function pkg_conf_path() {
    echo "${PACKAGES_DIR}/${1}.conf"
}

function pkg_exists() {
    [[ -f "$(pkg_conf_path "${1}")" ]]
}

##
# Read a field from a package definition file.
# Usage: pkg_read_field <name> <FIELD>
##
function pkg_read_field() {
    local NAME="${1}" FIELD="${2}"
    local CONF
    CONF="$(pkg_conf_path "${NAME}")"
    [[ -f "${CONF}" ]] || return 1
    # shellcheck disable=SC1090
    local VALUE=""
    VALUE=$(grep -E "^${FIELD}=" "${CONF}" | cut -d= -f2-)
    echo "${VALUE}"
}

##
# Ensure the package store directories exist.
##
function pkg_ensure_dirs() {
    if [[ ! -d "${PACKAGES_DIR}" ]]; then
        run mkdir -p "${PACKAGES_DIR}"
        run chmod 755 "${PACKAGES_DIR}"
    fi
    if [[ ! -d "${ASSIGNED_DIR}" ]]; then
        run mkdir -p "${ASSIGNED_DIR}"
        run chmod 755 "${ASSIGNED_DIR}"
    fi
}

##
# Create a new hosting package.
# Usage: create_package <name> --quota <MB> --sites <n> --dbs <n> [--bandwidth <GB>]
##
function create_package() {
    local NAME="${1:-}"
    shift || true

    if [[ -z "${NAME}" ]]; then
        error "Missing package name."
        echo "Usage: ${CMD_NAME} create <name> --quota <MB> --sites <n> --dbs <n> [--bandwidth <GB>]" >&2
        return 1
    fi
    pkg_validate_name "${NAME}" || return 1

    local QUOTA_MB="" MAX_SITES="" MAX_DBS="" BANDWIDTH_GB="0"
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --quota)
                QUOTA_MB="${2:-}"; shift 2 || shift
            ;;
            --sites)
                MAX_SITES="${2:-}"; shift 2 || shift
            ;;
            --dbs)
                MAX_DBS="${2:-}"; shift 2 || shift
            ;;
            --bandwidth)
                BANDWIDTH_GB="${2:-}"; shift 2 || shift
            ;;
            -h | --help)
                pkg_usage
                return 0
            ;;
            *)
                error "Unknown option '${1}'."
                return 1
            ;;
        esac
    done

    # Validate required fields.
    if [[ -z "${QUOTA_MB}" || -z "${MAX_SITES}" || -z "${MAX_DBS}" ]]; then
        error "Missing required options. --quota, --sites and --dbs are required."
        return 1
    fi
    if ! pkg_is_positive_int "${QUOTA_MB}"; then
        error "Invalid --quota '${QUOTA_MB}'. Must be a positive integer (MB)."
        return 1
    fi
    if ! pkg_is_nonneg_int "${MAX_SITES}"; then
        error "Invalid --sites '${MAX_SITES}'. Must be a non-negative integer."
        return 1
    fi
    if ! pkg_is_nonneg_int "${MAX_DBS}"; then
        error "Invalid --dbs '${MAX_DBS}'. Must be a non-negative integer."
        return 1
    fi
    if ! pkg_is_nonneg_int "${BANDWIDTH_GB}"; then
        error "Invalid --bandwidth '${BANDWIDTH_GB}'. Must be a non-negative integer (GB)."
        return 1
    fi

    if pkg_exists "${NAME}"; then
        error "Package '${NAME}' already exists."
        return 1
    fi

    pkg_ensure_dirs

    local CONF
    CONF="$(pkg_conf_path "${NAME}")"
    cat > "${CONF}" <<- EOL
# LEMPer hosting package: ${NAME}
# Generated by lemper-cli package create.
DISK_QUOTA_MB=${QUOTA_MB}
MAX_SITES=${MAX_SITES}
MAX_DATABASES=${MAX_DBS}
BANDWIDTH_GB=${BANDWIDTH_GB}
EOL
    run chmod 644 "${CONF}"

    success "Package '${NAME}' created: quota=${QUOTA_MB}MB, sites=${MAX_SITES}, databases=${MAX_DBS}, bandwidth=${BANDWIDTH_GB}GB."
}

##
# List all defined hosting packages.
##
function list_packages() {
    pkg_ensure_dirs

    local COUNT=0
    printf "%-20s %-12s %-8s %-8s %-12s\n" "PACKAGE" "QUOTA(MB)" "SITES" "DBS" "BANDWIDTH(GB)"
    printf "%-20s %-12s %-8s %-8s %-12s\n" "--------------------" "------------" "--------" "--------" "------------"

    local CONF NAME
    for CONF in "${PACKAGES_DIR}"/*.conf; do
        [[ -f "${CONF}" ]] || continue
        NAME="$(basename "${CONF}" .conf)"
        printf "%-20s %-12s %-8s %-8s %-12s\n" \
            "${NAME}" \
            "$(pkg_read_field "${NAME}" "DISK_QUOTA_MB")" \
            "$(pkg_read_field "${NAME}" "MAX_SITES")" \
            "$(pkg_read_field "${NAME}" "MAX_DATABASES")" \
            "$(pkg_read_field "${NAME}" "BANDWIDTH_GB")"
        COUNT=$((COUNT + 1))
    done

    if [[ "${COUNT}" -eq 0 ]]; then
        info "No hosting packages defined yet."
    fi
}

##
# Delete a hosting package and clean up stale assignment records.
# Usage: delete_package <name>
##
function delete_package() {
    local NAME="${1:-}"

    if [[ -z "${NAME}" ]]; then
        error "Missing package name."
        echo "Usage: ${CMD_NAME} delete <name>" >&2
        return 1
    fi
    pkg_validate_name "${NAME}" || return 1

    if ! pkg_exists "${NAME}"; then
        error "Package '${NAME}' does not exist."
        return 1
    fi

    run rm -f "$(pkg_conf_path "${NAME}")"

    # Clean up assignment records that referenced the deleted package.
    local ASSIGNED STALE_USER
    for ASSIGNED in "${ASSIGNED_DIR}"/*; do
        [[ -f "${ASSIGNED}" ]] || continue
        if grep -qx "PACKAGE=${NAME}" "${ASSIGNED}" 2>/dev/null; then
            STALE_USER="$(basename "${ASSIGNED}")"
            run rm -f "${ASSIGNED}"
            info "Removed stale package assignment for user '${STALE_USER}'."
        fi
    done

    success "Package '${NAME}' deleted."
}

##
# Make sure the 'quota' toolchain (setquota/quotaon) is available.
# Installs it via apt when missing. Returns non-zero when unavailable.
##
function pkg_ensure_quota_tools() {
    if command -v setquota >/dev/null 2>&1 && command -v quotaon >/dev/null 2>&1; then
        return 0
    fi

    info "Quota tools not found. Installing the 'quota' package..."
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive run apt-get install -q -y quota || {
            warn "Failed to install the 'quota' package. Disk quota will not be enforced."
            return 1
        }
    else
        warn "apt-get not available; cannot install the 'quota' package. Disk quota will not be enforced."
        return 1
    fi

    if ! command -v setquota >/dev/null 2>&1; then
        warn "Quota tools still unavailable after install attempt. Disk quota will not be enforced."
        return 1
    fi
    return 0
}

##
# Apply the package disk quota to a user's home directory via setquota.
# Degrades gracefully: warns and returns 0 (never fails the assignment)
# when quota tools are missing or the filesystem does not support quota.
# Usage: pkg_apply_disk_quota <user> <quota_mb>
##
function pkg_apply_disk_quota() {
    local USER="${1}" QUOTA_MB="${2}"

    pkg_ensure_quota_tools || return 0

    local HOME_DIR
    HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"
    if [[ -z "${HOME_DIR}" || ! -d "${HOME_DIR}" ]]; then
        warn "Home directory for user '${USER}' not found; skipping disk quota."
        return 0
    fi

    local MOUNT
    MOUNT="$(df --output=target "${HOME_DIR}" 2>/dev/null | tail -n 1)"
    if [[ -z "${MOUNT}" ]]; then
        warn "Could not determine filesystem for '${HOME_DIR}'; skipping disk quota."
        return 0
    fi

    # Try to enable quota accounting on the mount. This is a no-op when
    # already enabled; failure means the filesystem doesn't support quota
    # (or it isn't enabled in fstab) -> warn and continue without failing.
    if ! quotaon "${MOUNT}" >/dev/null 2>&1; then
        warn "Quota is not enabled on '${MOUNT}' (filesystem may not support quota). Skipping disk quota enforcement for '${USER}'."
        return 0
    fi

    # setquota expects block counts in 1K units: 1 MB = 1024 blocks.
    local BLOCKS=$((QUOTA_MB * 1024))
    if ! setquota -u "${USER}" "${BLOCKS}" "${BLOCKS}" 0 0 "${MOUNT}" >/dev/null 2>&1; then
        warn "setquota failed for user '${USER}' on '${MOUNT}'. Disk quota not enforced."
        return 0
    fi

    info "Disk quota of ${QUOTA_MB}MB applied to '${USER}' on '${MOUNT}'."
    return 0
}

##
# Assign a package to a system user and apply its disk quota.
# Usage: assign_package <user> <package>
##
function assign_package() {
    local USER="${1:-}" NAME="${2:-}"

    if [[ -z "${USER}" || -z "${NAME}" ]]; then
        error "Missing arguments."
        echo "Usage: ${CMD_NAME} assign <user> <package>" >&2
        return 1
    fi

    if ! id "${USER}" >/dev/null 2>&1; then
        error "User '${USER}' does not exist."
        return 1
    fi
    pkg_validate_name "${NAME}" || return 1
    if ! pkg_exists "${NAME}"; then
        error "Package '${NAME}' does not exist."
        return 1
    fi

    pkg_ensure_dirs

    local QUOTA_MB
    QUOTA_MB="$(pkg_read_field "${NAME}" "DISK_QUOTA_MB")"
    if ! pkg_is_positive_int "${QUOTA_MB}"; then
        error "Package '${NAME}' has an invalid DISK_QUOTA_MB value."
        return 1
    fi

    local ASSIGNED="${ASSIGNED_DIR}/${USER}"
    cat > "${ASSIGNED}" <<- EOL
# LEMPer package assignment for user: ${USER}
# Managed by lemper-cli package assign. Do not edit manually.
PACKAGE=${NAME}
ASSIGNED_AT=$(date +%s)
EOL
    run chmod 644 "${ASSIGNED}"

    # Enforce disk quota; never fails the assignment (graceful degradation).
    pkg_apply_disk_quota "${USER}" "${QUOTA_MB}"

    success "Package '${NAME}' assigned to user '${USER}'."
}

##
# Show the package assigned to a user.
# Usage: show_user_package <user>
##
function show_user_package() {
    local USER="${1:-}"

    if [[ -z "${USER}" ]]; then
        error "Missing user name."
        echo "Usage: ${CMD_NAME} info <user>" >&2
        return 1
    fi

    if ! id "${USER}" >/dev/null 2>&1; then
        error "User '${USER}' does not exist."
        return 1
    fi

    local ASSIGNED="${ASSIGNED_DIR}/${USER}"
    if [[ ! -f "${ASSIGNED}" ]]; then
        info "No package assigned to user '${USER}'."
        return 0
    fi

    local NAME
    NAME="$(grep -E "^PACKAGE=" "${ASSIGNED}" | cut -d= -f2-)"
    if [[ -z "${NAME}" ]]; then
        warn "Assignment record for '${USER}' is malformed."
        return 1
    fi

    echo "User:    ${USER}"
    echo "Package: ${NAME}"
    if pkg_exists "${NAME}"; then
        echo "  Disk quota (MB):  $(pkg_read_field "${NAME}" "DISK_QUOTA_MB")"
        echo "  Max sites:        $(pkg_read_field "${NAME}" "MAX_SITES")"
        echo "  Max databases:    $(pkg_read_field "${NAME}" "MAX_DATABASES")"
        echo "  Bandwidth (GB):   $(pkg_read_field "${NAME}" "BANDWIDTH_GB") (bookkeeping only)"
    else
        warn "Package '${NAME}' definition is missing (was deleted?)."
    fi
}

##
# Subcommand wrappers (lemper-site.sh style: site_subcmd_<name>).
##
function pkg_subcmd_create() { create_package "$@"; }
function pkg_subcmd_list()   { list_packages "$@"; }
function pkg_subcmd_delete() { delete_package "$@"; }
function pkg_subcmd_assign() { assign_package "$@"; }
function pkg_subcmd_info()   { show_user_package "$@"; }

function pkg_subcmd_help()    { pkg_usage; }
function pkg_subcmd_version() {
    if [[ "$(type -t cmd_version)" == "function" ]]; then
        cmd_version
    else
        echo "${CMD_NAME} (lemper-cli plugin)"
    fi
}

##
# 'package' subcommand dispatcher.
#
# Usage:
#   lemper-cli package <subcommand> [options] [<args>...]
##
function init_lemper_package() {
    if [[ -n "${1}" ]]; then
        local CMD="${1}"
        shift # Pass the remaining arguments to the subcommand.

        case "${CMD}" in
            help | -h | --help)
                pkg_subcmd_help
                exit 0
            ;;
            version | -v | --version)
                pkg_subcmd_version
                exit 0
            ;;
            create | list | delete | assign | info)
                "pkg_subcmd_${CMD}" "$@"
                exit $?
            ;;
            *)
                echo "${PROG_NAME:-lemper-cli} ${CMD_NAME}: '${CMD}' is not a valid subcommand." >&2
                echo "See '${PROG_NAME:-lemper-cli} ${CMD_NAME} --help' for more information." >&2
                exit 1
            ;;
        esac
    else
        echo "${PROG_NAME:-lemper-cli} ${CMD_NAME}: missing required arguments" >&2
        echo "See '${PROG_NAME:-lemper-cli} ${CMD_NAME} --help' for more information" >&2
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_package "$@"
