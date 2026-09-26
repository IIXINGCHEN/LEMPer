#!/usr/bin/env bash

# Node.js server installer
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

##
# Return the wanted Node.js major version from NODEJS_VERSION.
# Accepts "24" or "24.x" style values, defaults to 24 (LTS).
##
function nodejs_version_major() {
    local version="${NODEJS_VERSION:-24}"
    version="${version%.x}"
    echo "${version}"
}

##
# Add NodeSource Node.js repository.
# Uses the official NodeSource distribution method.
# Ref: https://github.com/nodesource/distributions/blob/master/README.md#deb
##
function add_nodejs_repo() {
    local NODEJS_MAJOR
    NODEJS_MAJOR=$(nodejs_version_major)

    local NODEJS_REPO_BASE="${NODESOURCE_REPO_BASE:-https://deb.nodesource.com}"
    local NODEJS_REPO_KEY_URL="${NODEJS_REPO_BASE}/gpgkey/nodesource-repo.gpg.key"
    local NODEJS_REPO_KEY_PATH="/usr/share/keyrings/nodesource.gpg"
    local NODEJS_REPO_FILE="/etc/apt/sources.list.d/nodesource.list"
    local NODEJS_PIN_FILE="/etc/apt/preferences.d/nodejs"
    local NODE_ARCH

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            NODE_ARCH=$(dpkg --print-architecture)
            if [[ "${NODE_ARCH}" != "amd64" && "${NODE_ARCH}" != "arm64" ]]; then
                error "Unable to add NodeSource repo, unsupported architecture: ${NODE_ARCH}. NodeSource only supports amd64 and arm64."
                exit 1
            fi

            if [[ ! -f "${NODEJS_REPO_FILE}" ]]; then
                echo "Adding NodeSource Node.js ${NODEJS_MAJOR}.x repository..."

                # Install pre-requisites.
                run apt-get install -q -y ca-certificates curl gnupg

                # Download and install the repository signing key.
                run bash -c "curl -fsSL ${NODEJS_REPO_KEY_URL} | gpg --dearmor --yes -o ${NODEJS_REPO_KEY_PATH}" && \
                run chmod 644 "${NODEJS_REPO_KEY_PATH}"

                # Add the repository to sources list.
                run bash -c "echo 'deb [arch=${NODE_ARCH} signed-by=${NODEJS_REPO_KEY_PATH}] ${NODEJS_REPO_BASE}/node_${NODEJS_MAJOR}.x nodistro main' > ${NODEJS_REPO_FILE}"

                # Prefer NodeSource nodejs package over the distro one (official setup method).
                # Pinned by suite (nodistro) so it also works with regional mirrors.
                run bash -c "printf 'Package: nodejs\nPin: release n=nodistro\nPin-Priority: 600\n' > ${NODEJS_PIN_FILE}"

                # Update package lists.
                run apt-get update -q -y
            else
                info "NodeSource Node.js repository already exists."
            fi
        ;;
        *)
            error "Unable to add NodeSource repo, unsupported release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

##
# Install Node.js.
##
function init_nodejs_install() {
    local DO_INSTALL_NODEJS=""
    local NODEJS_MAJOR
    NODEJS_MAJOR=$(nodejs_version_major)

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_NODEJS}" == true ]]; then
            DO_INSTALL_NODEJS="y"
        else
            DO_INSTALL_NODEJS="n"
        fi
    else
        while [[ "${DO_INSTALL_NODEJS}" != y* && "${DO_INSTALL_NODEJS}" != Y* && \
            "${DO_INSTALL_NODEJS}" != n* && "${DO_INSTALL_NODEJS}" != N* ]]; do
            read -rp "Do you want to install Node.js ${NODEJS_MAJOR}.x? [y/n]: " -e DO_INSTALL_NODEJS
        done
    fi

    if [[ ${DO_INSTALL_NODEJS} == y* || ${DO_INSTALL_NODEJS} == Y* ]]; then
        # Add NodeSource repository.
        add_nodejs_repo

        echo "Installing Node.js ${NODEJS_MAJOR}.x..."

        run apt-get install -q -y nodejs

        # Verify installation.
        if [[ "${DRYRUN}" == true ]]; then
            info "Node.js installed in dry run mode."
        else
            echo "Verifying Node.js installation..."
            if run node -v && run npm -v; then
                success "Node.js $(node -v) installed successfully."
            else
                info "Something went wrong with Node.js installation."
            fi
        fi
    else
        info "Node.js installation skipped."
    fi
}

echo "[Node.js Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
WANT_NODEJS_MAJOR="$(nodejs_version_major)"
if [[ -n $(command -v node) && "${FORCE_INSTALL}" != true ]]; then
    CURRENT_NODEJS_MAJOR="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${CURRENT_NODEJS_MAJOR}" == "${WANT_NODEJS_MAJOR}" ]]; then
        info "Node.js ${CURRENT_NODEJS_MAJOR}.x already exists, installation skipped."
    else
        info "Node.js ${CURRENT_NODEJS_MAJOR}.x found, wanted version is ${WANT_NODEJS_MAJOR}.x. Reinstalling..."
        init_nodejs_install "$@"
    fi
else
    init_nodejs_install "$@"
fi
