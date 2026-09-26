#!/usr/bin/env bash

# LEMPer Download Mirrors
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.0
#
# Central place for all download-mirror handling:
#  - automatic network region detection (China "cn" vs international "global"),
#  - per-source mirror base URLs (China mirrors are verified to exist),
#  - helper functions used by the installer scripts.
#
# This file is safe to source multiple times and safe to source standalone:
# every variable falls back to the official (global) upstream URL, so the
# installer behaves exactly as before when region detection is skipped or
# fails.

# Guard against double sourcing.
if [[ -n "${LEMPER_MIRRORS_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
LEMPER_MIRRORS_LOADED=1

# Probe endpoints used for auto region detection.
# Override LEMPER_CN_PROBE / LEMPER_GLOBAL_PROBE in tests to simulate regions.
LEMPER_CN_PROBE="${LEMPER_CN_PROBE:-https://mirrors.tuna.tsinghua.edu.cn}"
LEMPER_GLOBAL_PROBE="${LEMPER_GLOBAL_PROBE:-https://github.com}"
# Per-probe timeout in seconds; worst case auto detection takes ~2x this.
LEMPER_PROBE_TIMEOUT="${LEMPER_PROBE_TIMEOUT:-3}"

##
# Detect the network region: "cn" (China) or "global" (international).
# Honors MIRROR_REGION from .env: "auto" (default) | "cn" | "global".
# Never fails and never hangs longer than ~2 * LEMPER_PROBE_TIMEOUT.
# Always prints exactly one word: cn | global
##
function lemper_detect_region() {
    local configured="${MIRROR_REGION:-auto}"
    configured=$(echo "${configured}" | tr '[:upper:]' '[:lower:]')

    case "${configured}" in
        cn|china)
            echo "cn"
            return 0
            ;;
        global|intl|international|oversea|overseas)
            echo "global"
            return 0
            ;;
    esac

    # Auto detection: probe a well-known domestic mirror and an
    # international endpoint with short timeouts.
    local cn_ok=1 global_ok=1 cn_time="" global_time=""
    local probe_out probe_code probe_time

    if command -v curl >/dev/null 2>&1; then
        if probe_out=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
                --max-time "${LEMPER_PROBE_TIMEOUT}" \
                --connect-timeout "${LEMPER_PROBE_TIMEOUT}" \
                "${LEMPER_CN_PROBE}" 2>/dev/null); then
            probe_code=${probe_out%% *}
            probe_time=${probe_out##* }
            if [[ "${probe_code}" == [23]* ]]; then
                cn_ok=0
                cn_time=${probe_time}
            fi
        fi

        if probe_out=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
                --max-time "${LEMPER_PROBE_TIMEOUT}" \
                --connect-timeout "${LEMPER_PROBE_TIMEOUT}" \
                "${LEMPER_GLOBAL_PROBE}" 2>/dev/null); then
            probe_code=${probe_out%% *}
            probe_time=${probe_out##* }
            if [[ "${probe_code}" == [23]* ]]; then
                global_ok=0
                global_time=${probe_time}
            fi
        fi
    fi

    if [[ ${cn_ok} -eq 0 && ${global_ok} -ne 0 ]]; then
        echo "cn"
    elif [[ ${global_ok} -eq 0 && ${cn_ok} -ne 0 ]]; then
        echo "global"
    elif [[ ${cn_ok} -eq 0 && ${global_ok} -eq 0 ]]; then
        # Both reachable: use whichever answered faster.
        local faster
        faster=$(awk -v a="${cn_time}" -v b="${global_time}" \
            'BEGIN { if (a+0 <= 0) a=999; if (b+0 <= 0) b=999; print (a < b) ? "cn" : "global" }' 2>/dev/null || echo "global")
        echo "${faster:-global}"
    else
        # No network (or curl missing): keep current behavior.
        echo "global"
    fi
    return 0
}

##
# Return the regional base URL for a download source key.
# Usage: mirror_url <key>   e.g. mirror_url mongodb
##
function mirror_url() {
    local key="${1:-}"
    case "${key}" in
        mongodb)    echo "${MONGODB_REPO_BASE:-https://repo.mongodb.org/apt}" ;;
        postgres|pgdg) echo "${PGDG_REPO_BASE:-https://apt.postgresql.org/pub/repos/apt}" ;;
        redis)      echo "${REDIS_REPO_BASE:-https://packages.redis.io}" ;;
        redis_dl)   echo "${REDIS_DL_BASE:-https://download.redis.io}" ;;
        sury)       echo "${SURY_BASE:-https://packages.sury.org}" ;;
        myguard)    echo "${MYGUARD_BASE:-http://deb.myguard.nl}" ;;
        python)     echo "${PYTHON_DL_BASE:-https://www.python.org/ftp/python}" ;;
        go|golang)  echo "${GO_DL_BASE:-https://go.dev/dl}" ;;
        composer)   echo "${COMPOSER_INSTALLER_URL:-https://getcomposer.org/installer}" ;;
        pypi)       echo "${PIP_INDEX_URL:-https://pypi.org/simple}" ;;
        docker)     echo "${DOCKER_REPO_BASE:-https://download.docker.com}" ;;
        nginx)      echo "${NGINX_DL_BASE:-https://nginx.org/download}" ;;
        *)          echo "" ;;
    esac
}

##
# Rewrite a GitHub / raw.githubusercontent.com URL through the optional
# GITHUB_PROXY prefix (opt-in via .env). Returns the URL unchanged when
# no proxy is configured.
# Usage: gh_url "https://github.com/owner/repo/archive/v1.tar.gz"
##
function gh_url() {
    local url="${1:-}"
    local proxy="${GITHUB_PROXY:-}"
    if [[ -n "${proxy}" ]]; then
        proxy="${proxy%/}"
        case "${url}" in
            https://github.com/*|https://raw.githubusercontent.com/*)
                echo "${proxy}/${url}"
                return 0
                ;;
        esac
    fi
    echo "${url}"
}

##
# Detect the region once per process and export all mirror variables.
# Idempotent: subsequent calls are no-ops.
##
function lemper_init_mirrors() {
    if [[ -n "${LEMPER_REGION:-}" ]]; then
        return 0
    fi

    LEMPER_REGION=$(lemper_detect_region)
    export LEMPER_REGION

    # --- Per-source mirror bases (verified China mirrors) ---
    if [[ "${LEMPER_REGION}" == "cn" ]]; then
        MONGODB_REPO_BASE="https://mirrors.tuna.tsinghua.edu.cn/mongodb/apt"
        PGDG_REPO_BASE="https://mirrors.aliyun.com/postgresql/repos/apt"
        PYTHON_DL_BASE="https://registry.npmmirror.com/-/binary/python"
        GO_DL_BASE="https://mirrors.aliyun.com/golang"
        COMPOSER_INSTALLER_URL="https://install.phpcomposer.com/installer"
        PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
        BORINGSSL_BASE="https://github.com/google/boringssl/archive/refs/heads"
        # Docker: Aliyun docker-ce mirror (verified: serves noble/bookworm stable).
        DOCKER_REPO_BASE="https://mirrors.aliyun.com/docker-ce"
        # MariaDB: honor explicit .env override, else use verified CN mirror.
        if [[ -z "${MYSQL_REPO_MIRROR_URL:-}" ]]; then
            MYSQL_REPO_MIRROR_URL="https://mirrors.aliyun.com/mariadb"
        fi
    else
        MONGODB_REPO_BASE="https://repo.mongodb.org/apt"
        PGDG_REPO_BASE="https://apt.postgresql.org/pub/repos/apt"
        PYTHON_DL_BASE="https://www.python.org/ftp/python"
        GO_DL_BASE="https://go.dev/dl"
        COMPOSER_INSTALLER_URL="https://getcomposer.org/installer"
        PIP_INDEX_URL="https://pypi.org/simple"
        BORINGSSL_BASE="https://boringssl.googlesource.com/boringssl/+archive/refs/heads"
    fi

    # Sources without a China mirror keep the official URL in both regions.
    REDIS_REPO_BASE="https://packages.redis.io"
    REDIS_DL_BASE="http://download.redis.io"
    SURY_BASE="https://packages.sury.org"
    MYGUARD_BASE="http://deb.myguard.nl"
    NGINX_DL_BASE="https://nginx.org/download"

    export MONGODB_REPO_BASE PGDG_REPO_BASE PYTHON_DL_BASE GO_DL_BASE \
        COMPOSER_INSTALLER_URL PIP_INDEX_URL BORINGSSL_BASE \
        REDIS_REPO_BASE REDIS_DL_BASE SURY_BASE MYGUARD_BASE NGINX_DL_BASE \
        MYSQL_REPO_MIRROR_URL

    if [[ "$(type -t info)" == "function" ]]; then
        if [[ "${LEMPER_REGION}" == "cn" ]]; then
            info "Network region detected: China (cn) - using China download mirrors."
        else
            info "Network region detected: global - using official download sources."
        fi
    fi
    return 0
}

##
# Rewrite official Ubuntu/Debian archive hosts to a China mirror.
# Only runs when LEMPER_REGION=cn. Idempotent (re-runs are no-ops).
# APT_MIRROR_URL in .env overrides the default Tsinghua mirror base.
##
function lemper_apply_apt_mirrors() {
    if [[ "${LEMPER_REGION:-global}" != "cn" ]]; then
        return 0
    fi

    local mirror="${APT_MIRROR_URL:-https://mirrors.tuna.tsinghua.edu.cn}"
    mirror="${mirror%/}"

    if [[ "$(type -t info)" == "function" ]]; then
        info "Applying China APT archive mirrors (${mirror})..."
    fi

    local list_file
    for list_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "${list_file}" ]] || continue
        # NOTE: path-aware rules come first (archive.ubuntu.com serves the
        # archive under /ubuntu, while mirrors serve it under /<distro>).
        run sed -i \
            -e "s|https\?://archive\.ubuntu\.com/ubuntu|${mirror}/ubuntu|g" \
            -e "s|https\?://archive\.ubuntu\.com|${mirror}/ubuntu|g" \
            -e "s|https\?://security\.ubuntu\.com/ubuntu|${mirror}/ubuntu|g" \
            -e "s|https\?://security\.ubuntu\.com|${mirror}/ubuntu|g" \
            -e "s|https\?://ports\.ubuntu\.com/ubuntu-ports|${mirror}/ubuntu-ports|g" \
            -e "s|https\?://ports\.ubuntu\.com|${mirror}/ubuntu-ports|g" \
            -e "s|https\?://deb\.debian\.org/debian|${mirror}/debian|g" \
            -e "s|https\?://deb\.debian\.org|${mirror}/debian|g" \
            -e "s|https\?://security\.debian\.org/debian-security|${mirror}/debian-security|g" \
            -e "s|https\?://security\.debian\.org|${mirror}/debian-security|g" \
            "${list_file}"
    done
    return 0
}
