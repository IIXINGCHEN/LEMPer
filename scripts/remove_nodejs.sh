#!/usr/bin/env bash

# Node.js Uninstaller
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

function init_nodejs_removal() {
    # Remove NodeSource repository.
    echo "Removing NodeSource Node.js repository..."

    [ -f /etc/apt/sources.list.d/nodesource.list ] && run rm -f /etc/apt/sources.list.d/nodesource.list
    [ -f /etc/apt/sources.list.d/nodesource.sources ] && run rm -f /etc/apt/sources.list.d/nodesource.sources
    [ -f /etc/apt/preferences.d/nodejs ] && run rm -f /etc/apt/preferences.d/nodejs
    [ -f /etc/apt/preferences.d/nsolid ] && run rm -f /etc/apt/preferences.d/nsolid
    [ -f /usr/share/keyrings/nodesource.gpg ] && run rm -f /usr/share/keyrings/nodesource.gpg

    # Remove nodejs package.
    if dpkg-query -l | awk '/nodejs/ { print $2 }' | grep -qwE "^nodejs$"; then
        echo "Found nodejs package installation. Removing..."
        run apt-get purge -q -y nodejs && \
        run dpkg --purge nodejs
    else
        info "Node.js package not found."
    fi

    # Refresh package lists after removing the repository.
    run apt-get update -q -y

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v node) ]]; then
            success "Node.js removed succesfully."
        else
            info "Unable to remove Node.js."
        fi
    else
        info "Node.js removed in dry run mode."
    fi
}

echo "Uninstalling Node.js..."

if [[ -n $(command -v node) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_NODEJS="y"
    else
        while [[ "${REMOVE_NODEJS}" != "y" && "${REMOVE_NODEJS}" != "n" ]]; do
            read -rp "Are you sure to remove Node.js? [y/n]: " -e REMOVE_NODEJS
        done
    fi

    if [[ "${REMOVE_NODEJS}" == y* || "${REMOVE_NODEJS}" == Y* ]]; then
        init_nodejs_removal "$@"
    else
        echo "Found Node.js, but not removed."
    fi
else
    info "Oops, Node.js installation not found."
fi
