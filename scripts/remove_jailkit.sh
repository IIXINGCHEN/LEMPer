#!/usr/bin/env bash

# Jailkit Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.2.0

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

function init_jailkit_removal() {
    if dpkg-query -l | awk '/jailkit/ { print $2 }' | grep -qwE "^jailkit$"; then
        echo "Found jailkit package installation. Removing..."
        run apt-get purge -q -y jailkit && \
        run dpkg --purge jailkit
    else
        info "Jailkit package not found."
    fi

    # Remove the helper script installed by install_jailkit.sh.
    if [[ -f /usr/local/bin/lemper-jail-user ]]; then
        echo "Removing lemper-jail-user helper..."
        run rm -f /usr/local/bin/lemper-jail-user
    fi

    # Remove the chroot jail (contains jailed users' data).
    echo "Removing jailkit chroot jail..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_JAILKIT_JAIL="y"
        else
            REMOVE_JAILKIT_JAIL="n"
        fi
    else
        while [[ "${REMOVE_JAILKIT_JAIL}" != "y" && "${REMOVE_JAILKIT_JAIL}" != "n" ]]; do
            read -rp "Remove jailkit chroot jail (jailed users' data)? [y/n]: " -e REMOVE_JAILKIT_JAIL
        done
    fi

    if [[ "${REMOVE_JAILKIT_JAIL}" == y* || "${REMOVE_JAILKIT_JAIL}" == Y* ]]; then
        local JAIL_ROOT="${JAILKIT_JAIL_ROOT:-/home/jail}"
        if [[ -d "${JAIL_ROOT}" ]]; then
            run rm -fr "${JAIL_ROOT}"
        fi

        echo "Chroot jail deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v jk_init) ]]; then
            success "Jailkit removed successfully."
        else
            info "Unable to remove jailkit."
        fi
    else
        info "Jailkit removed in dry run mode."
    fi
}

echo "Uninstalling jailkit..."

if [[ -n $(command -v jk_init) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_JAILKIT="y"
    else
        while [[ "${REMOVE_JAILKIT}" != "y" && "${REMOVE_JAILKIT}" != "n" ]]; do
            read -rp "Are you sure to remove jailkit? [y/n]: " -e REMOVE_JAILKIT
        done
    fi

    if [[ "${REMOVE_JAILKIT}" == y* || "${REMOVE_JAILKIT}" == Y* ]]; then
        init_jailkit_removal "$@"
    else
        echo "Found jailkit, but not removed."
    fi
else
    info "Oops, jailkit installation not found."
fi
