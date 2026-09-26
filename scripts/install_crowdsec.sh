#!/usr/bin/env bash

# CrowdSec installer
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

##
# Add CrowdSec repository (packagecloud.io).
# Uses a manual repo file that mirrors what the official packagecloud setup
# script (https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh)
# would generate, instead of piping their script into bash.
# Ref: https://packagecloud.io/crowdsec/crowdsec
#      https://docs.crowdsec.net/docs/getting_started/install_crowdsec
##
function add_crowdsec_repo() {
    local CROWDSEC_GPG_KEY_URL="https://packagecloud.io/crowdsec/crowdsec/gpgkey"
    local CROWDSEC_KEYRING="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
    local CROWDSEC_REPO_FILE="/etc/apt/sources.list.d/crowdsec_crowdsec.list"
    local CROWDSEC_PIN_FILE="/etc/apt/preferences.d/crowdsec"

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "${CROWDSEC_REPO_FILE}" ]]; then
                echo "Adding CrowdSec repository..."

                # Create keyrings directory.
                run install -d -m 0755 /etc/apt/keyrings

                # Download the repository signing key.
                # The key is ASCII-armored, so it must be dearmored before use.
                # curl has a connect + total timeout and a clear error message
                # so a network hiccup (e.g. packagecloud blocked) is obvious.
                if ! curl -fsSL --connect-timeout 15 --max-time 120 \
                        -o /tmp/crowdsec-gpgkey.asc "${CROWDSEC_GPG_KEY_URL}"; then
                    error "Failed to download CrowdSec repository GPG key from ${CROWDSEC_GPG_KEY_URL}."
                    error "Check your network connection (packagecloud.io must be reachable) and try again."
                    exit 1
                fi

                if ! gpg --dearmor -o "${CROWDSEC_KEYRING}" /tmp/crowdsec-gpgkey.asc; then
                    error "Failed to dearmor the CrowdSec repository GPG key."
                    exit 1
                fi
                run chmod 0644 "${CROWDSEC_KEYRING}"
                run rm -f /tmp/crowdsec-gpgkey.asc

                # Add the repository to sources list.
                # Format mirrors packagecloud's generated config:
                #   deb [signed-by=<keyring>] https://packagecloud.io/crowdsec/crowdsec/<os>/ <dist> main
                run bash -c "echo 'deb [signed-by=${CROWDSEC_KEYRING}] https://packagecloud.io/crowdsec/crowdsec/${DISTRIB_NAME}/ ${RELEASE_NAME} main' > ${CROWDSEC_REPO_FILE}"

                # Pin the packagecloud repo above distro-provided crowdsec
                # (Ubuntu ships an older crowdsec in universe, per official docs).
                run bash -c "cat > ${CROWDSEC_PIN_FILE} <<'EOPIN'
Package: *
Pin: release o=packagecloud.io/crowdsec/crowdsec,a=any,n=any,c=main
Pin-Priority: 1001
EOPIN"

                # Update package lists.
                run apt-get update -q -y
            else
                info "CrowdSec repository already exists."
            fi
        ;;
        *)
            error "Unable to add CrowdSec repo, unsupported release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "CrowdSec installation skipped."
            exit 1
        ;;
    esac
}

##
# Install CrowdSec.
##
function init_crowdsec_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_CROWDSEC}" == true ]]; then
            local DO_INSTALL_CROWDSEC="y"
        else
            local DO_INSTALL_CROWDSEC="n"
        fi
    else
        while [[ "${DO_INSTALL_CROWDSEC}" != y* && "${DO_INSTALL_CROWDSEC}" != Y* && \
            "${DO_INSTALL_CROWDSEC}" != n* && "${DO_INSTALL_CROWDSEC}" != N* ]]; do
            read -rp "Do you want to install CrowdSec (intrusion prevention)? [y/n]: " -e DO_INSTALL_CROWDSEC
        done
    fi

    if [[ ${DO_INSTALL_CROWDSEC} == y* || ${DO_INSTALL_CROWDSEC} == Y* ]]; then
        # Coexistence note: fail2ban and CrowdSec overlap (both ban malicious IPs).
        if [[ "${INSTALL_FAIL2BAN}" == true ]]; then
            warning "Both CrowdSec and Fail2ban are enabled."
            warning "They overlap (both ban malicious IPs). Running both is supported,"
            warning "but it uses extra resources and may double-ban; consider using only one."
        fi

        # Add repository.
        add_crowdsec_repo

        echo "Installing CrowdSec..."

        # The firewall bouncer ships as iptables/nftables variants since 0.0.25;
        # nftables is the kernel default on Debian 10+ / Ubuntu 20.04+.
        run apt-get install -q -y crowdsec crowdsec-firewall-bouncer-nftables

        if [[ "${DRYRUN}" != true ]]; then
            echo "Configuring CrowdSec..."

            # Install the nginx collection so web-attack scenarios are active.
            run cscli hub update && \
            run cscli collections install crowdsecurity/nginx

            # Nginx log acquisition.
            # LEMPer stores nginx logs under /var/log/nginx/: the global error
            # log at /var/log/nginx/error.log and per-vhost access logs at
            # /var/log/nginx/*.access.log (e.g. localhost.access.log).
            # The global access_log is off in LEMPer's nginx.conf, so include
            # the default access.log path anyway for completeness.
            run mkdir -p /etc/crowdsec/acquis.d
            cat > /etc/crowdsec/acquis.d/lemper-nginx.yaml <<'EOACQ'
# Nginx log acquisition for LEMPer.
# LEMPer writes nginx logs to /var/log/nginx/.
filenames:
  - /var/log/nginx/access.log
  - /var/log/nginx/error.log
  - /var/log/nginx/*.access.log
labels:
  type: nginx
EOACQ

            # Register the firewall bouncer with the local API.
            local BOUNCER_NAME="lemper-firewall-bouncer"
            if ! cscli bouncers list 2>/dev/null | grep -qw "${BOUNCER_NAME}"; then
                echo "Registering firewall bouncer '${BOUNCER_NAME}'..."
                local BOUNCER_API_KEY=""
                if ! BOUNCER_API_KEY=$(cscli bouncers add -o raw "${BOUNCER_NAME}" 2>/dev/null); then
                    error "Failed to register CrowdSec bouncer '${BOUNCER_NAME}'."
                    error "Run 'cscli bouncers add ${BOUNCER_NAME}' manually and put the"
                    error "key in /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml."
                    exit 1
                fi

                local BOUNCER_YAML
                BOUNCER_YAML=$(find /etc/crowdsec/bouncers -maxdepth 1 -name '*firewall-bouncer*.yaml' 2>/dev/null | head -n 1)
                if [[ -n "${BOUNCER_YAML}" ]]; then
                    run sed -i "s|^api_key:.*|api_key: ${BOUNCER_API_KEY}|" "${BOUNCER_YAML}"
                else
                    error "Firewall bouncer config not found under /etc/crowdsec/bouncers/."
                    error "API key for '${BOUNCER_NAME}': ${BOUNCER_API_KEY}"
                    exit 1
                fi
            else
                info "Firewall bouncer '${BOUNCER_NAME}' already registered."
            fi

            # Detect the bouncer systemd unit name (varies by package variant).
            local BOUNCER_SERVICE="crowdsec-firewall-bouncer"
            if [[ ! -f "/lib/systemd/system/${BOUNCER_SERVICE}.service" && \
                  ! -f "/etc/systemd/system/${BOUNCER_SERVICE}.service" && \
                  -f "/lib/systemd/system/crowdsec-firewall-bouncer-nftables.service" ]]; then
                BOUNCER_SERVICE="crowdsec-firewall-bouncer-nftables"
            fi

            # Enable and start services.
            echo "Starting CrowdSec..."
            run systemctl enable crowdsec && \
            run systemctl start crowdsec && \
            run systemctl enable "${BOUNCER_SERVICE}" && \
            run systemctl start "${BOUNCER_SERVICE}"
            sleep 3

            # Verify.
            if cscli bouncers list 2>/dev/null | grep -qw "${BOUNCER_NAME}" && \
                [[ $(pgrep -c crowdsec) -gt 0 ]]; then
                success "CrowdSec installed successfully."
            else
                info "Something went wrong with CrowdSec installation."
            fi
        else
            info "CrowdSec installed in dry run mode."
        fi
    else
        info "CrowdSec installation skipped."
    fi
}

echo "[CrowdSec Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v cscli) && "${FORCE_INSTALL}" != true ]]; then
    info "CrowdSec already exists, installation skipped."
else
    init_crowdsec_install "$@"
fi
