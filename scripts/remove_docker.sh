#!/usr/bin/env bash

# Remove Docker Engine + Docker Compose plugin
# Min. Requirement  : GNU/Linux Ubuntu 20.04 / Debian 11
# Last Build        : 25/09/2026
# Author            : LEMPer Stack
# Since Version     : 2.6.0

# Include helper functions.
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
# shellcheck disable=SC1091
. "${BASE_DIR}/utils.sh"

# Make sure only root can run this remover script.
requires_root "$@"

# Make sure only supported distribution can run this remover script.
preflight_system_check

##
# Remove Docker Engine + Compose plugin.
# Container data in /var/lib/docker is kept unless DOCKER_PURGE_DATA=true.
##
function init_docker_remove() {
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            DO_REMOVE_DOCKER="y"
        else
            DO_REMOVE_DOCKER="n"
        fi
    else
        while [[ "${DO_REMOVE_DOCKER}" != "y" && "${DO_REMOVE_DOCKER}" != "Y" && \
            "${DO_REMOVE_DOCKER}" != "n" && "${DO_REMOVE_DOCKER}" != "N" ]]; do
            read -rp "Do you want to remove Docker Engine + Compose? [y/n]: " -e DO_REMOVE_DOCKER
        done
    fi

    if [[ ${DO_REMOVE_DOCKER} == y* || ${DO_REMOVE_DOCKER} == Y* ]]; then
        echo "Removing Docker Engine + Docker Compose plugin..."

        # Stop the daemon first.
        # NOTE: Do not use the 'run' wrapper here - it exits on failure,
        # which would defeat the || fallbacks below.
        systemctl stop docker 2>/dev/null || service docker stop 2>/dev/null || true
        systemctl disable docker 2>/dev/null || true

        run apt-get purge -q -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null || true
        run apt-get autoremove -q -y

        # Remove the APT repository and keyring.
        run rm -f "/etc/apt/sources.list.d/docker-${RELEASE_NAME}.list"
        run rm -f /etc/apt/keyrings/docker.asc

        # Remove the docker group: its members otherwise keep an easy path back
        # to root-equivalent access if Docker is ever reinstalled.
        if getent group docker >/dev/null 2>&1; then
            groupdel docker 2>/dev/null || \
                warning "Could not remove the 'docker' group; check its members manually."
        fi

        if [[ "${DOCKER_PURGE_DATA:-false}" == true ]]; then
            warn "Purging Docker data directories /var/lib/docker and /home/docker ..."
            run rm -rf /var/lib/docker /var/lib/containerd /home/docker
        else
            info "Docker data kept in /var/lib/docker and /home/docker (set DOCKER_PURGE_DATA=true to wipe it)."
        fi

        success "Docker Engine removed."
    else
        echo "Docker Engine removal skipped."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -z $(command -v docker) ]]; then
    info "Docker is not installed, removal skipped."
else
    init_docker_remove "$@"
fi
