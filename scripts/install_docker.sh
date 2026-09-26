#!/usr/bin/env bash

# Install Docker Engine + Docker Compose plugin
# Min. Requirement  : GNU/Linux Ubuntu 20.04 / Debian 11
# Last Build        : 25/09/2026
# Author            : LEMPer Stack
# Since Version     : 2.6.0

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
# Add the official Docker APT repository.
# Uses DOCKER_REPO_BASE so China/global mirror logic applies
# (see scripts/lemper-mirrors.sh).
##
function add_docker_repo() {
    echo "Adding Docker APT repository..."

    local DOCKER_REPO_BASE=${DOCKER_REPO_BASE:-"https://download.docker.com"}

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/docker-${RELEASE_NAME}.list" ]]; then
                run install -m 0755 -d /etc/apt/keyrings && \
                run curl -fsSL -o "/etc/apt/keyrings/docker.asc" "${DOCKER_REPO_BASE}/linux/${DISTRIB_NAME}/gpg" && \
                run chmod a+r /etc/apt/keyrings/docker.asc && \
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH} signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_REPO_BASE}/linux/${DISTRIB_NAME} ${RELEASE_NAME} stable' > /etc/apt/sources.list.d/docker-${RELEASE_NAME}.list"
                success "Docker repository added (${DOCKER_REPO_BASE})."
            else
                info "Docker repository already exists."
            fi

            run apt-get update -q -y
        ;;
        *)
            fail "Unable to add Docker repository, '${DISTRIB_NAME}' is not supported."
        ;;
    esac
}

##
# Optionally configure a Docker Hub registry mirror.
# Only written when DOCKER_REGISTRY_MIRROR is set in .env; never hardcoded.
##
function configure_docker_registry_mirror() {
    local REGISTRY_MIRROR=${DOCKER_REGISTRY_MIRROR:-""}

    [[ -z "${REGISTRY_MIRROR}" ]] && return 0

    echo "Configuring Docker registry mirror: ${REGISTRY_MIRROR}"
    run mkdir -p /etc/docker

    if [[ -f /etc/docker/daemon.json ]]; then
        warn "/etc/docker/daemon.json already exists, registry mirror not overwritten."
        return 0
    fi

    run bash -c "cat > /etc/docker/daemon.json <<EOL
{
    \"registry-mirrors\": [\"${REGISTRY_MIRROR}\"]
}
EOL"
    success "Docker registry mirror configured."
}

##
# Install Docker Engine + Compose plugin.
##
function init_docker_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_DOCKER}" == true ]]; then
            DO_INSTALL_DOCKER="y"
        else
            DO_INSTALL_DOCKER="n"
        fi
    else
        while [[ "${DO_INSTALL_DOCKER}" != "y" && "${DO_INSTALL_DOCKER}" != "Y" && \
            "${DO_INSTALL_DOCKER}" != "n" && "${DO_INSTALL_DOCKER}" != "N" ]]; do
            read -rp "Do you want to install Docker Engine + Compose? [y/n]: " -e DO_INSTALL_DOCKER
        done
    fi

    if [[ ${DO_INSTALL_DOCKER} == y* || ${DO_INSTALL_DOCKER} == Y* ]]; then
        echo "Installing Docker Engine + Docker Compose plugin..."

        # Resolve regional repo base (China/global) when mirror helper is loaded.
        if [[ "$(type -t mirror_url)" == "function" ]]; then
            DOCKER_REPO_BASE=$(mirror_url docker)
            export DOCKER_REPO_BASE
        fi

        add_docker_repo

        if [[ ${DRYRUN} != true ]]; then
            run apt-get install -q -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin

            # Write registry mirror config BEFORE starting the daemon so it
            # takes effect on first start (no restart needed).
            configure_docker_registry_mirror

            # Enable and start the Docker daemon.
            # NOTE: Do not use the 'run' wrapper here - it exits on failure,
            # which would defeat the || fallbacks below.
            if [[ "$(type -t enable_service)" == "function" ]]; then
                enable_service docker
            else
                systemctl enable docker 2>/dev/null || true
                systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
            fi

            # Allow the LEMPer admin user to run docker without sudo.
            if [[ -n "${LEMPER_USERNAME:-}" ]] && id "${LEMPER_USERNAME}" &>/dev/null; then
                run usermod -aG docker "${LEMPER_USERNAME}"
                info "User '${LEMPER_USERNAME}' added to the docker group (re-login to take effect)."
            fi

            if docker --version &>/dev/null && docker compose version &>/dev/null; then
                success "Docker Engine + Compose plugin installed."
                docker --version
                docker compose version
            else
                warn "Docker installed but the daemon check failed."
            fi
        else
            echo "Docker Engine installation skipped in dry run mode."
        fi
    else
        echo "Docker Engine installation skipped."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
# Require both the engine and the compose plugin; repair if compose is missing.
if [[ -n $(command -v docker) ]] && docker compose version &>/dev/null && [[ "${FORCE_INSTALL}" != true ]]; then
    info "Docker already exists, installation skipped."
else
    init_docker_install "$@"
fi
