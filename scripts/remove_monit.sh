#!/usr/bin/env bash

# Monit Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 20.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.6

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

function init_monit_removal() {
    # Stop monit process.
    if [[ $(pgrep -c monit) -gt 0 ]]; then
        echo "Stopping Monit..."
        run systemctl stop monit
        run systemctl disable monit
    fi

    if dpkg-query -l | awk '/monit/ { print $2 }' | grep -qwE "^monit$"; then
        echo "Found monit package installation. Removing..."
        run apt-get purge -q -y monit && \
        run dpkg --purge monit
    else
        info "Monit package not found."
    fi

    # Remove Monit configuration.
    echo "Removing Monit configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_MONIT_CONFIG="y"
        else
            REMOVE_MONIT_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_MONIT_CONFIG}" != "y" && "${REMOVE_MONIT_CONFIG}" != "n" ]]; do
            read -rp "Remove Monit configuration files? [y/n]: " -e REMOVE_MONIT_CONFIG
        done
    fi

    if [[ "${REMOVE_MONIT_CONFIG}" == y* || "${REMOVE_MONIT_CONFIG}" == Y* ]]; then
        if [ -f /etc/monit/conf.d/lemper ]; then
            run rm -f /etc/monit/conf.d/lemper
        fi

        if [ -d /etc/monit/ ]; then
            run rm -fr /etc/monit/
        fi

        echo "All configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v monit) ]]; then
            success "Monit server removed successfully."
        else
            info "Unable to remove Monit server."
        fi
    else
        info "Monit server removed in dry run mode."
    fi
}

echo "Uninstalling Monit server..."

if [[ -n $(command -v monit) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_MONIT="y"
    else
        while [[ "${REMOVE_MONIT}" != "y" && "${REMOVE_MONIT}" != "n" ]]; do
            read -rp "Are you sure to remove Monit? [y/n]: " -e REMOVE_MONIT
        done
    fi

    if [[ "${REMOVE_MONIT}" == y* || "${REMOVE_MONIT}" == Y* ]]; then
        init_monit_removal "$@"
    else
        echo "Found Monit server, but not removed."
    fi
else
    info "Oops, Monit installation not found."
fi
