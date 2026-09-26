#!/usr/bin/env bash

# CrowdSec Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 20.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.7.0

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

function init_crowdsec_removal() {
    # Stop CrowdSec processes (best effort, ignore failures).
    if [[ $(pgrep -c crowdsec) -gt 0 ]]; then
        echo "Stopping CrowdSec..."
        systemctl stop crowdsec 2>/dev/null || true
        systemctl disable crowdsec 2>/dev/null || true
        systemctl stop crowdsec-firewall-bouncer 2>/dev/null || true
        systemctl disable crowdsec-firewall-bouncer 2>/dev/null || true
        systemctl stop crowdsec-firewall-bouncer-nftables 2>/dev/null || true
        systemctl disable crowdsec-firewall-bouncer-nftables 2>/dev/null || true
    fi

    if dpkg-query -l | awk '/crowdsec/ { print $2 }' | grep -qwE "^crowdsec$"; then
        echo "Found CrowdSec package installation. Removing..."
        run apt-get purge -q -y crowdsec \
            crowdsec-firewall-bouncer crowdsec-firewall-bouncer-iptables \
            crowdsec-firewall-bouncer-nftables
        dpkg --purge crowdsec 2>/dev/null || true
    else
        info "CrowdSec package not found."
    fi

    # Remove CrowdSec APT repository, pin and signing key.
    echo "Removing CrowdSec repository..."
    [ -f /etc/apt/sources.list.d/crowdsec_crowdsec.list ] && \
        run rm -f /etc/apt/sources.list.d/crowdsec_crowdsec.list
    [ -f /etc/apt/preferences.d/crowdsec ] && \
        run rm -f /etc/apt/preferences.d/crowdsec
    [ -f /etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg ] && \
        run rm -f /etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg
    [ -f /etc/apt/trusted.gpg.d/crowdsec_crowdsec.gpg ] && \
        run rm -f /etc/apt/trusted.gpg.d/crowdsec_crowdsec.gpg

    run apt-get update -q -y

    # Remove CrowdSec config files.
    echo "Removing CrowdSec configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_CROWDSEC_CONFIG="y"
        else
            REMOVE_CROWDSEC_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_CROWDSEC_CONFIG}" != "y" && "${REMOVE_CROWDSEC_CONFIG}" != "n" ]]; do
            read -rp "Remove CrowdSec configuration files? [y/n]: " -e REMOVE_CROWDSEC_CONFIG
        done
    fi

    if [[ "${REMOVE_CROWDSEC_CONFIG}" == y* || "${REMOVE_CROWDSEC_CONFIG}" == Y* ]]; then
        if [ -d /etc/crowdsec/ ]; then
            run rm -fr /etc/crowdsec/
        fi

        if [ -d /var/lib/crowdsec/ ]; then
            run rm -fr /var/lib/crowdsec/
        fi

        echo "All configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v cscli) ]]; then
            success "CrowdSec removed succesfully."
        else
            info "Unable to remove CrowdSec."
        fi
    else
        info "CrowdSec removed in dry run mode."
    fi
}

echo "Uninstalling CrowdSec..."

if [[ -n $(command -v cscli) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_CROWDSEC="y"
    else
        while [[ "${REMOVE_CROWDSEC}" != "y" && "${REMOVE_CROWDSEC}" != "n" ]]; do
            read -rp "Are you sure to remove CrowdSec? [y/n]: " -e REMOVE_CROWDSEC
        done
    fi

    if [[ "${REMOVE_CROWDSEC}" == y* || "${REMOVE_CROWDSEC}" == Y* ]]; then
        init_crowdsec_removal "$@"
    else
        echo "Found CrowdSec, but not removed."
    fi
else
    info "Oops, CrowdSec installation not found."
fi
