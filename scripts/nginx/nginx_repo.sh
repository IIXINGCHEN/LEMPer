#!/usr/bin/env bash

# Nginx Repository Management
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Add Ondrej's Nginx repository.
##
function add_nginx_repo_ondrej() {
    echo "Add Ondrej's Nginx repository..."

    # Nginx version.
    local NGINX_VERSION=${NGINX_VERSION:-"stable"}

    if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
        local NGINX_REPO="nginx-mainline"
    else
        local NGINX_REPO="nginx"
    fi

    case "${DISTRIB_NAME}" in
        debian)
            if [[ ! -f "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list" ]]; then
                run curl -sSL -o "/etc/apt/trusted.gpg.d/ondrej-${NGINX_REPO}.gpg" "${SURY_BASE:-https://packages.sury.org}/${NGINX_REPO}/apt.gpg" && \
                run touch "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb ${SURY_BASE:-https://packages.sury.org}/${NGINX_REPO}/ ${RELEASE_NAME} main' > /etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
        ;;
        ubuntu)
            # Nginx custom with ngx cache purge from Ondrej repo.
            run curl -sSL -o "/etc/apt/trusted.gpg.d/ondrej-${NGINX_REPO}.gpg" "${SURY_BASE:-https://packages.sury.org}/${NGINX_REPO}/apt.gpg" && \
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C && \
            run add-apt-repository -y "ppa:ondrej/${NGINX_REPO}" && \
            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Add MyGuard's Nginx repository.
##
function add_nginx_repo_myguard() {
    echo "Add MyGuard's Nginx repository..."

    # Nginx version.
    NGINX_VERSION=${NGINX_VERSION:-"stable"}

    # MyGuard only has one repo for nginx
    local NGINX_REPO="nginx"

    DISTRIB_ARCH=$(get_distrib_arch)

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list" ]]; then
                run curl -sSL -o "/etc/apt/trusted.gpg.d/deb.myguard.nl.gpg" "${MYGUARD_BASE:-http://deb.myguard.nl}/pool/deb.myguard.nl.gpg" && \
                run touch "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH}] ${MYGUARD_BASE:-http://deb.myguard.nl} ${RELEASE_NAME} main' > /etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
            else
                info "${NGINX_REPO} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKGS=("nginx" "nginx-common")
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Add official nginx.org repository (stable or mainline branch).
# The stable branch (even minor, e.g. 1.30.x) receives only critical
# bug and security fixes - the LTS-aligned choice for production.
##
function add_nginx_repo_official() {
    echo "Add official nginx.org repository..."

    # Nginx branch: stable (even minor) or mainline (odd minor).
    # Official repo layout (https://nginx.org/en/linux_packages.html):
    #   stable   -> https://nginx.org/packages/<distro>
    #   mainline -> https://nginx.org/packages/mainline/<distro>
    local NGINX_VERSION=${NGINX_VERSION:-"stable"}

    if [[ ${NGINX_VERSION} == "mainline" || ${NGINX_VERSION} == "latest" ]]; then
        local NGINX_BRANCH="mainline"
        local NGINX_REPO_URL="https://nginx.org/packages/mainline/${DISTRIB_NAME}"
    else
        local NGINX_BRANCH="stable"
        local NGINX_REPO_URL="https://nginx.org/packages/${DISTRIB_NAME}"
    fi

    DISTRIB_ARCH=$(get_distrib_arch)

    case "${DISTRIB_NAME}" in
        debian | ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/nginx-official-${RELEASE_NAME}.list" ]]; then
                run curl -fsSL -o "/usr/share/keyrings/nginx-signing.key.asc" "https://nginx.org/keys/nginx_signing.key" && \
                run gpg --dearmor --yes -o "/usr/share/keyrings/nginx-archive-keyring.gpg" "/usr/share/keyrings/nginx-signing.key.asc" && \
                run rm -f "/usr/share/keyrings/nginx-signing.key.asc" && \
                run chmod 644 "/usr/share/keyrings/nginx-archive-keyring.gpg" && \
                run touch "/etc/apt/sources.list.d/nginx-official-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [arch=${DISTRIB_ARCH} signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] ${NGINX_REPO_URL} ${RELEASE_NAME} nginx' > /etc/apt/sources.list.d/nginx-official-${RELEASE_NAME}.list"
            else
                info "nginx.org ${NGINX_BRANCH} repository already exists."
            fi

            run apt-get update -q -y
            NGINX_PKGS=("nginx")
        ;;
        *)
            fail "Unable to add Nginx, this GNU/Linux distribution is not supported."
        ;;
    esac
}

##
# Extra module packages for the official nginx.org repository.
# nginx.org ships a limited set of dynamic modules (nginx-module-*);
# stream and mail are compiled into the official binary.
# Modules not shipped by nginx.org are skipped with a warning -
# use the source-build installer (NGINX_INSTALLER=source) for the full set.
##
function get_official_extra_module_packages() {
    EXTRA_MODULE_PKGS=()
    local mod_missing="not shipped by nginx.org repo; skipped (use source build for this module)"

    echo "Determining extra module packages (nginx.org official repo)..." >&2

    "${NGX_HTTP_AUTH_PAM:-false}" && warning "auth-pam module ${mod_missing}."
    "${NGX_HTTP_BROTLI:-false}" && warning "brotli module ${mod_missing}."
    "${NGX_HTTP_CACHE_PURGE:-false}" && warning "cache-purge module ${mod_missing}."
    "${NGX_HTTP_DAV_EXT:-false}" && warning "dav-ext module ${mod_missing}."
    "${NGX_HTTP_ECHO:-false}" && warning "echo module ${mod_missing}."
    "${NGX_HTTP_FANCYINDEX:-false}" && warning "fancyindex module ${mod_missing}."
    "${NGX_HTTP_GEOIP2:-false}" && warning "geoip2 module ${mod_missing}."
    "${NGX_HTTP_HEADERS_MORE:-false}" && warning "headers-more module ${mod_missing}."
    "${NGX_HTTP_LUA:-false}" && warning "lua module ${mod_missing}."
    "${NGX_HTTP_NAXSI:-false}" && warning "naxsi module ${mod_missing}."
    "${NGX_HTTP_NDK:-false}" && warning "ndk module ${mod_missing}."
    "${NGX_HTTP_REDIS2:-false}" && warning "redis2 module ${mod_missing}."
    "${NGX_HTTP_SUBS_FILTER:-false}" && warning "subs-filter module ${mod_missing}."
    "${NGX_HTTP_UPSTREAM_FAIR:-false}" && warning "upstream-fair module ${mod_missing}."
    "${NGX_HTTP_VTS:-false}" && warning "vhost-traffic-status module ${mod_missing}."
    "${NGX_NCHAN:-false}" && warning "nchan module ${mod_missing}."
    "${NGX_RTMP:-false}" && warning "rtmp module ${mod_missing}."

    if "${NGX_HTTP_GEOIP:-false}"; then
        if apt-cache show nginx-module-geoip >/dev/null 2>&1; then
            echo "  Adding: nginx-module-geoip" >&2
            EXTRA_MODULE_PKGS+=("libmaxminddb0" "libmaxminddb-dev" "nginx-module-geoip")
        else
            warning "nginx-module-geoip not available in repo; skipped."
        fi
    fi

    if "${NGX_HTTP_IMAGE_FILTER:-false}"; then
        if apt-cache show nginx-module-image-filter >/dev/null 2>&1; then
            echo "  Adding: nginx-module-image-filter" >&2
            EXTRA_MODULE_PKGS+=("nginx-module-image-filter")
        else
            warning "nginx-module-image-filter not available in repo; skipped."
        fi
    fi

    if "${NGX_HTTP_NJS:-false}"; then
        if apt-cache show nginx-module-njs >/dev/null 2>&1; then
            echo "  Adding: nginx-module-njs" >&2
            EXTRA_MODULE_PKGS+=("nginx-module-njs")
        else
            warning "nginx-module-njs not available in repo; skipped."
        fi
    fi

    if "${NGX_HTTP_XSLT_FILTER:-false}"; then
        if apt-cache show nginx-module-xslt >/dev/null 2>&1; then
            echo "  Adding: nginx-module-xslt" >&2
            EXTRA_MODULE_PKGS+=("nginx-module-xslt")
        else
            warning "nginx-module-xslt not available in repo; skipped."
        fi
    fi

    if "${NGX_HTTP_MEMCACHED:-false}"; then
        warning "ngx-http-memcached module is not supported in repo install."
    fi

    if "${NGX_HTTP_PASSENGER:-false}"; then
        if [[ -n $(command -v passenger-config) ]]; then
            echo "  Passenger found..." >&2
        else
            error "Passenger not found. Skipped..."
        fi
    fi

    # Mail and stream are compiled into the official nginx.org binary.
    "${NGX_MAIL:-false}" && echo "  mail: built into the official nginx binary" >&2
    "${NGX_STREAM:-false}" && echo "  stream: built into the official nginx binary" >&2

    echo "Total extra modules: ${#EXTRA_MODULE_PKGS[@]}" >&2
}

##
# Build extra module packages list from repository
# Populates EXTRA_MODULE_PKGS array based on enabled modules
# Note: All debug messages go to stderr to avoid polluting package list
##
function get_repo_extra_module_packages() {
    local SELECTED_REPO="${1:-ondrej}"
    EXTRA_MODULE_PKGS=()

    # Official nginx.org repository has its own module package set.
    if [[ "${SELECTED_REPO}" == "official" || "${SELECTED_REPO}" == "nginx" ]]; then
        get_official_extra_module_packages
        return 0
    fi

    echo "Determining extra module packages..." >&2

    # Auth PAM
    if "${NGX_HTTP_AUTH_PAM:-false}"; then
        echo "  Adding: libnginx-mod-http-auth-pam" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-auth-pam")
    fi

    # Brotli compression
    if "${NGX_HTTP_BROTLI:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-brotli" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-brotli")
        else
            echo "  Adding: libnginx-mod-brotli" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-brotli")
        fi
    fi

    # Cache Purge
    if "${NGX_HTTP_CACHE_PURGE:-false}"; then
        echo "  Adding: libnginx-mod-http-cache-purge" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-cache-purge")
    fi

    # DAV Ext
    if "${NGX_HTTP_DAV_EXT:-false}"; then
        echo "  Adding: libnginx-mod-http-dav-ext" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-dav-ext")
    fi

    # Echo
    if "${NGX_HTTP_ECHO:-false}"; then
        echo "  Adding: libnginx-mod-http-echo" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-echo")
    fi

    # Fancy indexes
    if "${NGX_HTTP_FANCYINDEX:-false}"; then
        echo "  Adding: libnginx-mod-http-fancyindex" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-fancyindex")
    fi

    # GeoIP
    if "${NGX_HTTP_GEOIP:-false}"; then
        echo "  Adding: libnginx-mod-http-geoip" >&2
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip" "libnginx-mod-stream-geoip")
    fi

    # GeoIP2
    if "${NGX_HTTP_GEOIP2:-false}"; then
        echo "  Adding: libnginx-mod-http-geoip2" >&2
        EXTRA_MODULE_PKGS+=("libmaxminddb0" "libmaxminddb-dev" "libnginx-mod-http-geoip2" "libnginx-mod-stream-geoip2")
    fi

    # Headers more
    if "${NGX_HTTP_HEADERS_MORE:-false}"; then
        echo "  Adding: libnginx-mod-http-headers-more-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-headers-more-filter")
    fi

    # Image filter
    if "${NGX_HTTP_IMAGE_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-image-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-image-filter")
    fi

    # Lua
    if "${NGX_HTTP_LUA:-false}"; then
        echo "  Adding: libnginx-mod-http-lua" >&2
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            EXTRA_MODULE_PKGS+=("luarocks" "lua-cjson" "lua-resty" "lua-resty-core" "lua-resty-lrucache" "libnginx-mod-http-lua")
        else
            EXTRA_MODULE_PKGS+=("luajit" "luarocks" "lua-cjson" "lua-resty-core" "lua-resty-lrucache" "libnginx-mod-http-lua")
        fi
    fi

    # Memcached
    if "${NGX_HTTP_MEMCACHED:-false}"; then
        warning "ngx-http-memcached module is not supported in repo install."
    fi

    # NAXSI
    if "${NGX_HTTP_NAXSI:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-naxsi" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-naxsi")
        fi
    fi

    # NDK
    if "${NGX_HTTP_NDK:-false}"; then
        echo "  Adding: libnginx-mod-http-ndk" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-ndk")
    fi

    # NJS
    if "${NGX_HTTP_NJS:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-njs" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-njs")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-njs module. Skipped..."
        fi
    fi

    # Passenger
    if "${NGX_HTTP_PASSENGER:-false}"; then
        if [[ -n $(command -v passenger-config) ]]; then
            echo "  Passenger found..." >&2
        else
            error "Passenger not found. Skipped..."
        fi
    fi

    # Redis2
    if "${NGX_HTTP_REDIS2:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-redis2" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-redis2")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-redis2 module. Skipped..."
        fi
    fi

    # Subs filter
    if "${NGX_HTTP_SUBS_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-subs-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-subs-filter")
    fi

    # Upstream fair
    if "${NGX_HTTP_UPSTREAM_FAIR:-false}"; then
        echo "  Adding: libnginx-mod-http-upstream-fair" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-upstream-fair")
    fi

    # VTS
    if "${NGX_HTTP_VTS:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-vhost-traffic-status" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-vhost-traffic-status")
        else
            error "${SELECTED_REPO} doesn't have libnginx-mod-http-vhost-traffic-status module. Skipped..."
        fi
    fi

    # XSLT
    if "${NGX_HTTP_XSLT_FILTER:-false}"; then
        echo "  Adding: libnginx-mod-http-xslt-filter" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-http-xslt-filter")
    fi

    # Mail
    if "${NGX_MAIL:-false}"; then
        echo "  Adding: libnginx-mod-mail" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-mail")
    fi

    # Nchan
    if "${NGX_NCHAN:-false}"; then
        echo "  Adding: libnginx-mod-nchan" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-nchan")
    fi

    # RTMP
    if "${NGX_RTMP:-false}"; then
        if [[ "${SELECTED_REPO}" == "myguard" ]]; then
            echo "  Adding: libnginx-mod-http-flv-live" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-http-flv-live")
        else
            echo "  Adding: libnginx-mod-rtmp" >&2
            EXTRA_MODULE_PKGS+=("libnginx-mod-rtmp")
        fi
    fi

    # Stream
    if "${NGX_STREAM:-false}"; then
        echo "  Adding: libnginx-mod-stream" >&2
        EXTRA_MODULE_PKGS+=("libnginx-mod-stream")
    fi

    echo "Total extra modules: ${#EXTRA_MODULE_PKGS[@]}" >&2
}

##
# Install Nginx from repository
##
function install_nginx_from_repo() {
    local SELECTED_REPO="${1:-ondrej}"

    echo "Installing Nginx from ${SELECTED_REPO} repository..."

    if [[ -n "${NGINX_PKGS[*]}" ]]; then
        # Build extra module packages list if enabled
        if "${NGINX_EXTRA_MODULES:-false}"; then
            echo "Checking for extra modules..."
            get_repo_extra_module_packages "${SELECTED_REPO}"
        fi

        # Install Nginx packages
        if [[ ${#EXTRA_MODULE_PKGS[@]} -gt 0 ]]; then
            echo "Installing Nginx with ${#EXTRA_MODULE_PKGS[@]} extra module packages..."
            run apt-get install -q -y "${NGINX_PKGS[@]}" "${EXTRA_MODULE_PKGS[@]}"
        else
            echo "Installing Nginx (no extra modules)..."
            run apt-get install -q -y "${NGINX_PKGS[@]}"
        fi
    fi
}
