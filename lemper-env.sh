#!/usr/bin/env bash
#
# LEMPer Production .env Manager
#
# Generates and manages a production-ready .env from .env.dist:
#   - auto-generates strong random passwords for every secret field
#   - auto-detects server hostname and public IP
#   - forces ENVIRONMENT=production
#   - validates the result before you deploy
#
# Usage:
#   ./lemper-env.sh init [--profile minimal|standard|full]
#                        [--enable nodejs,docker,...] [--disable redis,...]
#                        [--php "8.4"] [--default-php 8.4]
#                        [--db mariadb:12.3] [--region auto|cn|global]
#                        [--hostname FQDN] [--ip IP] [--email addr]
#                        [--ssh-port 2269] [--yes] [--install]
#   ./lemper-env.sh rotate                 # regenerate all passwords (backup first)
#   ./lemper-env.sh validate               # production-readiness check
#   ./lemper-env.sh show                   # display .env with secrets masked
#   ./lemper-env.sh set KEY VALUE          # change one value (backup first)
#
# Profiles (applied on top of .env.dist defaults):
#   minimal  - bare LEMP stack only (nginx + php + mariadb), all extras off
#   standard - production default: + certbot SSL, firewall, mailer, redis,
#              composer, imagemagick, pure-ftpd
#   full     - everything on: + nodejs, crowdsec, backup, monit, jailkit,
#              docker, bbr, postgres, mongodb, memcached
# --enable/--disable fine-tune individual features after the profile.
#
# Never commit the generated .env to version control.

set -euo pipefail

PROG_NAME="lemper-env"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIST="${BASE_DIR}/.env.dist"
ENV_FILE="${BASE_DIR}/.env"

# Password fields that must always hold a strong generated secret.
PASSWORD_KEYS=(
    LEMPER_PASSWORD
    MYSQL_ROOT_PASSWORD
    MARIABACKUP_PASS
    POSTGRES_DB_PASS
    MEMCACHED_PASSWORD
    MONGODB_ADMIN_PASSWORD
    REDIS_PASSWORD
    BACKUP_PASSWORD
)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

info()  { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

die() { error "$*"; exit 1; }

require_env_dist() {
    [[ -f "${ENV_DIST}" ]] || die ".env.dist not found in ${BASE_DIR}. Run from the LEMPer root."
}

# Generate a cryptographically strong password (alphanumeric, 32 chars).
# Alphanumeric-only keeps it safe inside shell quoting, SQL, Redis/Mongo URIs.
gen_password() {
    local len="${1:-32}" pw=""
    if command -v openssl >/dev/null 2>&1; then
        pw=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c "${len}")
    fi
    if [[ ${#pw} -lt ${len} ]]; then
        pw=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${len}")
    fi
    [[ ${#pw} -ge ${len} ]] || die "failed to generate a secure password"
    printf '%s' "${pw}"
}

# Set KEY="value" in the env file (replaces the whole line, keeps file tidy).
set_env_var() {
    local file="$1" key="$2" value="$3"
    # Key must be a plain shell identifier: no regex/sed injection.
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid key name: ${key}"
    # A .env value is single-line; refuse newlines rather than corrupting the file.
    if [[ "${value}" == *$'\n'* ]]; then
        die "value for ${key} contains a newline, refusing to write it to .env"
    fi
    # Escape backslashes and double quotes for the double-quoted .env form.
    # Fixed-string rewrite: the value never passes through a sed replacement.
    local esc=${value//\\/\\\\}
    esc=${esc//\"/\\\"}
    local tmp
    tmp=$(mktemp)
    grep -vE "^${key}=" "${file}" > "${tmp}" || true
    printf '%s="%s"\n' "${key}" "${esc}" >> "${tmp}"
    mv -f "${tmp}" "${file}"
    chmod 600 "${file}"
}

get_env_var() {
    local file="$1" key="$2"
    grep -E "^${key}=" "${file}" 2>/dev/null | head -1 \
        | sed -E "s/^${key}=//; s/^\"//; s/\"$//" || true
}

backup_env() {
    if [[ -f "${ENV_FILE}" ]]; then
        local bak="${ENV_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp -f "${ENV_FILE}" "${bak}"
        chmod 600 "${bak}"
        info "Existing .env backed up to $(basename "${bak}")"
        # keep only the 5 newest backups
        ls -t "${ENV_FILE}".bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f
    fi
}

detect_public_ip() {
    local ip=""
    ip=$(curl -s --max-time 4 https://ifconfig.me 2>/dev/null \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -1 || true)
    if [[ -z "${ip}" ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1 || true)
    fi
    printf '%s' "${ip}"
}

detect_hostname() {
    local hn=""
    hn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)
    printf '%s' "${hn}"
}

# Canonical feature name -> .env key mapping for --enable/--disable/--profile.
feature_key() {
    case "$1" in
        nodejs)      printf 'INSTALL_NODEJS' ;;
        crowdsec)    printf 'INSTALL_CROWDSEC' ;;
        backup)      printf 'INSTALL_BACKUP_TOOL' ;;
        monit)       printf 'INSTALL_MONIT' ;;
        jailkit)     printf 'INSTALL_JAILKIT' ;;
        docker)      printf 'INSTALL_DOCKER' ;;
        bbr)         printf 'ENABLE_BBR' ;;
        postgres)    printf 'INSTALL_POSTGRES' ;;
        redis)       printf 'INSTALL_REDIS' ;;
        mongodb)     printf 'INSTALL_MONGODB' ;;
        memcached)   printf 'INSTALL_MEMCACHED' ;;
        ftp)         printf 'INSTALL_FTP_SERVER' ;;
        mailer)      printf 'INSTALL_MAILER' ;;
        certbot)     printf 'INSTALL_CERTBOT' ;;
        fw|firewall) printf 'INSTALL_FW' ;;
        imagemagick) printf 'INSTALL_IMAGEMAGICK' ;;
        composer)    printf 'INSTALL_PHP_COMPOSER' ;;
        *)           return 1 ;;
    esac
}

ALL_FEATURES="nodejs crowdsec backup monit jailkit docker bbr postgres redis mongodb memcached ftp mailer certbot fw imagemagick composer"
STANDARD_FEATURES="certbot fw mailer redis composer imagemagick ftp"

# apply_profile <name>: set feature flags per profile. Call after .env.dist copy.
apply_profile() {
    local profile="$1" f key
    case "${profile}" in
        minimal)
            for f in ${ALL_FEATURES}; do
                key=$(feature_key "${f}") && set_env_var "${ENV_FILE}" "${key}" "false"
            done
            info "Profile 'minimal': bare LEMP stack, all extra features off." ;;
        standard)
            for f in ${ALL_FEATURES}; do
                key=$(feature_key "${f}") || continue
                if [[ " ${STANDARD_FEATURES} " == *" ${f} "* ]]; then
                    set_env_var "${ENV_FILE}" "${key}" "true"
                else
                    set_env_var "${ENV_FILE}" "${key}" "false"
                fi
            done
            info "Profile 'standard': production default feature set." ;;
        full)
            for f in ${ALL_FEATURES}; do
                key=$(feature_key "${f}") && set_env_var "${ENV_FILE}" "${key}" "true"
            done
            info "Profile 'full': every feature enabled." ;;
        *) die "--profile must be minimal, standard or full" ;;
    esac
}

# apply_feature_list <csv> <true|false>: --enable / --disable handling.
apply_feature_list() {
    local csv="$1" state="$2" f key
    [[ -z "${csv}" ]] && return 0
    local IFS=','
    for f in ${csv}; do
        f=$(printf '%s' "${f}" | tr -d ' ')
        [[ -z "${f}" ]] && continue
        key=$(feature_key "${f}") || die "unknown feature: ${f} (see --help)"
        set_env_var "${ENV_FILE}" "${key}" "${state}"
        info "Feature '${f}' -> ${state}"
    done
}

confirm() {
    local prompt="$1"
    [[ "${ASSUME_YES:-false}" == "true" ]] && return 0
    local ans=""
    read -r -p "${prompt} [y/N] " ans
    [[ "${ans}" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------

cmd_init() {
    local php_versions="8.4" default_php="8.4"
    local db_server="mariadb" db_version="12.3"
    local region="auto" hostname="" ip="" email="" ssh_port="2269"
    local profile="standard" enable_list="" disable_list=""
    local do_install=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)      profile="$2"; shift 2 ;;
            --enable)       enable_list="$2"; shift 2 ;;
            --disable)      disable_list="$2"; shift 2 ;;
            --php)          php_versions="$2"; shift 2 ;;
            --default-php)  default_php="$2"; shift 2 ;;
            --db)           db_server="${2%%:*}"; db_version="${2##*:}"; shift 2 ;;
            --region)       region="$2"; shift 2 ;;
            --hostname)     hostname="$2"; shift 2 ;;
            --ip)           ip="$2"; shift 2 ;;
            --email)        email="$2"; shift 2 ;;
            --ssh-port)     ssh_port="$2"; shift 2 ;;
            --yes)          ASSUME_YES=true; shift ;;
            --install)      do_install=true; shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              die "unknown option: $1 (see --help)" ;;
        esac
    done

    require_env_dist

    case "${db_server}" in
        mariadb|mysql) ;;
        *) die "--db must be mariadb:<ver> or mysql:<ver>" ;;
    esac
    case "${region}" in
        auto|cn|global) ;;
        *) die "--region must be auto, cn or global" ;;
    esac
    [[ "${default_php}" == "${php_versions}"* || "${php_versions}" == *"${default_php}"* ]] \
        || die "--default-php ${default_php} is not in --php \"${php_versions}\""

    if [[ -z "${hostname}" ]]; then
        hostname=$(detect_hostname)
        info "Detected hostname: ${hostname:-<none>}"
    fi
    if [[ -z "${ip}" ]]; then
        info "Detecting public IP..."
        ip=$(detect_public_ip)
        info "Detected IP: ${ip:-<none>}"
    fi
    if [[ -z "${email}" && "${ASSUME_YES:-false}" != "true" ]]; then
        read -r -p "Admin email address: " email
    fi

    echo ""
    info "This will generate a PRODUCTION .env with fresh secrets."
    confirm "Continue?" || die "aborted."

    backup_env
    cp -f "${ENV_DIST}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"

    # --- production hardening ---
    set_env_var "${ENV_FILE}" "ENVIRONMENT" "production"
    set_env_var "${ENV_FILE}" "SERVER_HOSTNAME" "${hostname}"
    set_env_var "${ENV_FILE}" "SERVER_IP" "${ip}"
    set_env_var "${ENV_FILE}" "TIMEZONE" "$(cat /etc/timezone 2>/dev/null || echo UTC)"
    set_env_var "${ENV_FILE}" "MIRROR_REGION" "${region}"
    set_env_var "${ENV_FILE}" "PHP_VERSIONS" "${php_versions}"
    set_env_var "${ENV_FILE}" "DEFAULT_PHP_VERSION" "${default_php}"
    set_env_var "${ENV_FILE}" "MYSQL_SERVER" "${db_server}"
    set_env_var "${ENV_FILE}" "MYSQL_VERSION" "${db_version}"
    set_env_var "${ENV_FILE}" "SSH_PORT" "${ssh_port}"
    [[ -n "${email}" ]] && set_env_var "${ENV_FILE}" "LEMPER_ADMIN_EMAIL" "${email}"

    # --- feature profile (minimal|standard|full) + --enable/--disable tweaks ---
    apply_profile "${profile}"
    apply_feature_list "${enable_list}" "true"
    apply_feature_list "${disable_list}" "false"

    # --- fresh secrets for every password field ---
    local key pw
    for key in "${PASSWORD_KEYS[@]}"; do
        pw=$(gen_password 32)
        set_env_var "${ENV_FILE}" "${key}" "${pw}"
    done

    info "Production .env generated (mode 600)."
    echo ""
    if ! cmd_validate; then
        warn "Validation reported issues above - fix them before installing."
    fi

    if [[ "${do_install}" == "true" ]]; then
        echo ""
        confirm "Run ./install.sh now?" || die "aborted before install."
        exec "${BASE_DIR}/install.sh"
    else
        echo ""
        info "Next: review with './lemper-env.sh show', then run './lemper-env.sh validate' and './install.sh'."
    fi
}

cmd_rotate() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes) ASSUME_YES=true; shift ;;
            *)     die "unknown option: $1" ;;
        esac
    done
    [[ -f "${ENV_FILE}" ]] || die ".env not found - run './lemper-env.sh init' first."
    warn "This will REPLACE all passwords in .env with newly generated ones."
    warn "Services using the old passwords (MySQL, Redis, ...) will need reconfiguration."
    confirm "Continue?" || die "aborted."
    backup_env
    local key pw
    for key in "${PASSWORD_KEYS[@]}"; do
        pw=$(gen_password 32)
        set_env_var "${ENV_FILE}" "${key}" "${pw}"
    done
    chmod 600 "${ENV_FILE}"
    info "All passwords rotated. Remember to update dependent services and your password manager."
}

cmd_validate() {
    [[ -f "${ENV_FILE}" ]] || die ".env not found - run './lemper-env.sh init' first."
    local ok=true val

    check() { # check <test-name> <condition(0=pass)>
        if [[ "$2" -eq 0 ]]; then info "OK: $1"; else error "FAIL: $1"; ok=false; fi
    }

    val=$(get_env_var "${ENV_FILE}" "ENVIRONMENT")
    check "ENVIRONMENT=production" "$([[ "${val}" == "production" ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "SERVER_HOSTNAME")
    if [[ "${val}" == *.* && -n "${val}" ]]; then
        info "OK: SERVER_HOSTNAME is set (${val})"
        [[ "${val}" == *example* ]] && warn "hostname contains 'example' - make sure it is your real FQDN"
    else
        error "FAIL: SERVER_HOSTNAME must be a valid FQDN (e.g. host.domain.com)"; ok=false
    fi

    val=$(get_env_var "${ENV_FILE}" "SERVER_IP")
    check "SERVER_IP is set" "$([[ "${val}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "LEMPER_ADMIN_EMAIL")
    check "LEMPER_ADMIN_EMAIL is real (not example.com)" "$([[ -n "${val}" && "${val}" != *@example.com ]] && echo 0 || echo 1)"

    local key kval allpw=true
    for key in "${PASSWORD_KEYS[@]}"; do
        kval=$(get_env_var "${ENV_FILE}" "${key}")
        if [[ ${#kval} -lt 16 ]]; then allpw=false; error "FAIL: ${key} looks weak or empty"; fi
    done
    ${allpw} && info "OK: all ${#PASSWORD_KEYS[@]} password fields hold strong secrets"

    val=$(get_env_var "${ENV_FILE}" "MIRROR_REGION")
    check "MIRROR_REGION is auto|cn|global" "$([[ "${val}" =~ ^(auto|cn|global)$ ]] && echo 0 || echo 1)"

    # --- feature flags must be exactly true/false ---
    local fkey fval allbool=true
    for f in nodejs crowdsec backup monit jailkit docker bbr postgres redis mongodb \
             memcached ftp mailer certbot fw imagemagick composer; do
        fkey=$(feature_key "${f}") || continue
        fval=$(get_env_var "${ENV_FILE}" "${fkey}")
        if [[ "${fval}" != "true" && "${fval}" != "false" ]]; then
            allbool=false; error "FAIL: ${fkey} must be true/false (got '${fval}')"
        fi
    done
    ${allbool} && info "OK: all feature flags are true/false"

    val=$(get_env_var "${ENV_FILE}" "MYSQL_SERVER")
    check "MYSQL_SERVER is mariadb|mysql" "$([[ "${val}" =~ ^(mariadb|mysql)$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "BACKUP_SCHEDULE")
    check "BACKUP_SCHEDULE is daily|weekly" "$([[ "${val}" =~ ^(daily|weekly)$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "NODEJS_VERSION")
    check "NODEJS_VERSION is numeric" "$([[ "${val}" =~ ^[0-9]+$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "PHP_FPM_CPU_QUOTA")
    check "PHP_FPM_CPU_QUOTA empty or N%" "$([[ -z "${val}" || "${val}" =~ ^[0-9]+%$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "PHP_FPM_MEMORY_MAX")
    check "PHP_FPM_MEMORY_MAX empty or N[M|G]" "$([[ -z "${val}" || "${val}" =~ ^[0-9]+[MG]$ ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "DOCKER_REGISTRY_MIRROR")
    check "DOCKER_REGISTRY_MIRROR empty or http(s) URL" \
        "$([[ -z "${val}" || "${val}" =~ ^https?:// ]] && echo 0 || echo 1)"

    if [[ "$(get_env_var "${ENV_FILE}" "INSTALL_FTP_SERVER")" == "true" ]]; then
        val=$(get_env_var "${ENV_FILE}" "FTP_SERVER_NAME")
        check "FTP_SERVER_NAME is vsftpd|pureftpd" \
            "$([[ "${val}" =~ ^(vsftpd|pureftpd|pure-ftpd)$ ]] && echo 0 || echo 1)"
    fi

    # --- production gotchas (warnings, not failures) ---
    if [[ "$(get_env_var "${ENV_FILE}" "INSTALL_DOCKER")" == "true" && \
          "$(get_env_var "${ENV_FILE}" "INSTALL_FW")" == "true" ]]; then
        warn "Docker bypasses UFW by writing iptables rules directly - published container ports are reachable even with 'ufw default deny incoming'. Bind sensitive containers to 127.0.0.1 or manage filtering via DOCKER-USER chain."
    fi
    if [[ "$(get_env_var "${ENV_FILE}" "INSTALL_CROWDSEC")" == "true" ]]; then
        warn "CrowdSec overlaps with fail2ban (both ban abusive IPs) - running both is allowed but review jail/bouncer overlap."
    fi

    local phpv defphp
    phpv=$(get_env_var "${ENV_FILE}" "PHP_VERSIONS")
    defphp=$(get_env_var "${ENV_FILE}" "DEFAULT_PHP_VERSION")
    check "DEFAULT_PHP_VERSION (${defphp}) is in PHP_VERSIONS" \
        "$([[ "${phpv}" == *"${defphp}"* ]] && echo 0 || echo 1)"

    val=$(get_env_var "${ENV_FILE}" "RSA_PUB_KEY")
    if [[ "${val}" == "copy your ssh public rsa key here" ]]; then
        warn "RSA_PUB_KEY is still the placeholder (only matters if SSH_PASSWORDLESS=true)"
    fi

    if [[ -f "${BASE_DIR}/.env.bak" || -n "$(ls "${ENV_FILE}".bak.* 2>/dev/null)" ]]; then
        info "OK: .env backup exists"
    else
        warn "no .env backup found"
    fi

    # permissions: .env must not be world-readable (it holds secrets)
    local perm
    perm=$(stat -c %a "${ENV_FILE}" 2>/dev/null || stat -f %Lp "${ENV_FILE}")
    check ".env permissions are 600" "$([[ "${perm}" == "600" ]] && echo 0 || echo 1)"

    ${ok} && info "Validation PASSED - ready for production install." || error "Validation FAILED."
    ${ok}
}

cmd_show() {
    [[ -f "${ENV_FILE}" ]] || die ".env not found - run './lemper-env.sh init' first."
    local line key
    while IFS= read -r line; do
        if [[ "${line}" =~ ^([A-Z_]+)= ]]; then
            key="${BASH_REMATCH[1]}"
            case "${key}" in
                *PASSWORD*|*PASSWD*|*PASS_*|*_PASS|*SECRET*|*PRIVATE*|RSA_PUB_KEY|*_KEY)
                    printf '%s="********"\n' "${key}" ;;
                *)  printf '%s\n' "${line}" ;;
            esac
        else
            printf '%s\n' "${line}"
        fi
    done < "${ENV_FILE}"
}

cmd_set() {
    [[ $# -eq 2 ]] || die "usage: ./lemper-env.sh set KEY VALUE"
    [[ -f "${ENV_FILE}" ]] || die ".env not found - run './lemper-env.sh init' first."
    backup_env
    set_env_var "${ENV_FILE}" "$1" "$2"
    chmod 600 "${ENV_FILE}"
    info "Set $1 in .env"
}

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

[[ $# -ge 1 ]] || { usage; exit 1; }
cmd="$1"; shift
case "${cmd}" in
    init)     cmd_init "$@" ;;
    rotate)   cmd_rotate "$@" ;;
    validate) cmd_validate "$@" ;;
    show)     cmd_show "$@" ;;
    set)      cmd_set "$@" ;;
    -h|--help|help) usage ;;
    *)        die "unknown command: ${cmd} (init|rotate|validate|show|set)" ;;
esac
