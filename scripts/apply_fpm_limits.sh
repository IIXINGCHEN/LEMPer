#!/usr/bin/env bash

# Apply systemd cgroup resource limits to PHP-FPM services.
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.2.0
#
# This snippet is sourced by install.sh after the PHP installation. For every
# installed PHP version's phpX.Y-fpm.service it writes a systemd drop-in:
#   /etc/systemd/system/phpX.Y-fpm.service.d/limits.conf
# applying:
#   PHP_FPM_CPU_QUOTA   -> [Service] CPUQuota=   (e.g. "50%")
#   PHP_FPM_MEMORY_MAX  -> [Service] MemoryMax=  (e.g. "512M")
#
# Both variables are optional. When both are empty this script is a safe
# no-op (no files are written, no daemon-reload is triggered).
#
# After limits are applied, systemd is reloaded (daemon-reload). The new
# limits take effect on the next service restart; running PHP-FPM processes
# keep their current limits until restarted, e.g.:
#   systemctl restart php8.4-fpm
#
# Environment:
#   PHP_VERSIONS        - space-separated PHP versions (e.g. "8.3 8.4 8.5").
#   PHP_FPM_CPU_QUOTA   - systemd CPUQuota value, empty disables.
#   PHP_FPM_MEMORY_MAX  - systemd MemoryMax value, empty disables.

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this script.
    requires_root "$@"

    # Make sure only supported distribution can run this script.
    preflight_system_check
fi

##
# Write systemd drop-in resource limits for each installed PHP-FPM service.
##
function apply_fpm_limits() {
    # No limits configured: safe no-op.
    if [[ -z "${PHP_FPM_CPU_QUOTA:-}" && -z "${PHP_FPM_MEMORY_MAX:-}" ]]; then
        info "No PHP-FPM resource limits configured (PHP_FPM_CPU_QUOTA/PHP_FPM_MEMORY_MAX empty), skipping."
        return 0
    fi

    local PHPv="" FPM_UNIT="" DROPIN_DIR="" APPLIED=0
    local FPM_VERSIONS=()

    # shellcheck disable=SC2206
    read -r -a FPM_VERSIONS <<< "${PHP_VERSIONS:-}"

    if [[ "${#FPM_VERSIONS[@]}" -eq 0 ]]; then
        info "No PHP versions defined (PHP_VERSIONS empty), skipping."
        return 0
    fi

    for PHPv in "${FPM_VERSIONS[@]}"; do
        FPM_UNIT="php${PHPv}-fpm"

        if [[ ! -f "/lib/systemd/system/${FPM_UNIT}.service" ]]; then
            info "Service ${FPM_UNIT} not installed, skipping."
            continue
        fi

        DROPIN_DIR="/etc/systemd/system/${FPM_UNIT}.service.d"
        run mkdir -p "${DROPIN_DIR}"

        echo "Applying resource limits to ${FPM_UNIT}..."

        if [[ "${DRYRUN}" != true ]]; then
            {
                echo "[Service]"
                [[ -n "${PHP_FPM_CPU_QUOTA:-}" ]] && echo "CPUQuota=${PHP_FPM_CPU_QUOTA}"
                [[ -n "${PHP_FPM_MEMORY_MAX:-}" ]] && echo "MemoryMax=${PHP_FPM_MEMORY_MAX}"
            } > "${DROPIN_DIR}/limits.conf"
            run chmod 0644 "${DROPIN_DIR}/limits.conf"
        else
            info "Would write ${DROPIN_DIR}/limits.conf (dry run)."
        fi

        APPLIED=1
    done

    if [[ "${APPLIED}" == "1" ]]; then
        run systemctl daemon-reload
        success "PHP-FPM resource limits applied. Restart each php*-fpm service for the limits to take effect."
    fi
}

echo "[PHP-FPM Resource Limits]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
apply_fpm_limits "$@"
