#!/usr/bin/env bash

# PHP Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 15/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Define build directory.
BUILD_DIR=${BUILD_DIR:-"/usr/local/src/lemper"}
if [ ! -d "${BUILD_DIR}" ]; then
    run mkdir -p "${BUILD_DIR}"
fi

# Make sure only root can run this installer script.
requires_root

function add_php_repo() {
    # Add PHP (latest stable) from Ondrej's repo
    # Source: https://launchpad.net/~ondrej/+archive/ubuntu/php

    echo "Add Ondrej's PHP repository..."

    if "${DRYRUN}"; then
        warning "PHP repository added in dryrun mode."
    else
        {
            # Fix for NO_PUBKEY key servers error
            run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 4F4EA0AAE5267A6C
            run add-apt-repository -y ppa:ondrej/php
            run apt-get update -y
        }
    fi
}

function install_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi
    local PHP_PKGS=()
    export PHP_IS_INSTALLED="no"

    # Checking if php already installed.
    if [[ -n $(command -v "php${PHPv}") ]]; then
        PHP_IS_INSTALLED="yes"
        warning "PHP${PHPv} & FPM package already installed..."
    else
        echo "Installing PHP${PHPv} & FPM..."

        # Add repo first
        DISTRIB_REPO=${DISTRIB_REPO:-$(get_release_name)}
        if [ ! -f "/etc/apt/sources.list.d/ondrej-php-${DISTRIB_REPO}.list" ]; then
            add_php_repo
        fi

        PHP_PKGS=("php${PHPv} php${PHPv}-bcmath php${PHPv}-cli php${PHPv}-common \
php${PHPv}-curl php${PHPv}-dev php${PHPv}-fpm php${PHPv}-mysql php${PHPv}-gd \
php${PHPv}-gmp php${PHPv}-imap php${PHPv}-intl php${PHPv}-json php${PHPv}-ldap \
php${PHPv}-mbstring php${PHPv}-opcache php${PHPv}-pspell php${PHPv}-readline \
php${PHPv}-recode php${PHPv}-snmp php${PHPv}-soap php${PHPv}-sqlite3 \
php${PHPv}-tidy php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-zip \
php-geoip php-pear pkg-php-tools spawn-fcgi fcgiwrap geoip-database" "${PHP_PKGS[@]}")

        if [[ "${#PHP_PKGS[@]}" -gt 0 ]]; then
            echo "Installing PHP${PHPv} & FPM packages..."
            # shellcheck disable=SC2068
            run apt-get install -y ${PHP_PKGS[@]}
        fi

        if [[ -n $(command -v "php${PHPv}") ]]; then
            status "PHP${PHPv} & FPM packages installed."
        fi

        # Install php mcrypt?
        echo ""
        while [[ $INSTALL_PHPMCRYPT != "y" && $INSTALL_PHPMCRYPT != "n" ]]; do
            read -rp "Do you want to install PHP Mcrypt for encryption/decryption? [y/n]: " \
                -i n -e INSTALL_PHPMCRYPT
        done
        echo ""

        if [[ "$INSTALL_PHPMCRYPT" == Y* || "$INSTALL_PHPMCRYPT" == y* ]]; then
            if [ "${PHPv//.}" -lt "72" ]; then
                run apt-get install -y "php${PHPv}-mcrypt"
            elif [ "${PHPv}" == "7.2" ]; then
                run apt-get -y install gcc make autoconf libc-dev pkg-config \
                    libmcrypt-dev libreadline-dev && \
                    pecl install mcrypt-1.0.1

                # Enable Mcrypt module.
                echo "Update PHP ini file with Mcrypt module..."
                run bash -c "echo extension=mcrypt.so > /etc/php/${PHPv}/mods-available/mcrypt.ini"

                if [ ! -f "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/mcrypt.ini" \
                        "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini"
                fi

                if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/mcrypt.ini" \
                        "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini"
                fi
            else
                run apt-get install -y dh-php

                # use libsodium instead
                warning "Mcrypt is deprecated for PHP version ${PHPv} or greater, you should using Libsodium or OpenSSL."
            fi
        fi

        if [ ! -d /var/log/php ]; then
            mkdir /var/log/php
        fi
    fi
}

# Install ionCube Loader
function install_ioncube() {
    echo "Installing ionCube PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Removing old/existing ionCube PHP loader..."
        run rm -fr /usr/lib/php/loaders/ioncube
    fi

    run pushd "${BUILD_DIR}"

    ARCH=${ARCH:-$(uname -p)}
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86-64.tar.gz
        run rm -f ioncube_loaders_lin_x86-64.tar.gz
    else
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86.tar.gz
        run rm -f ioncube_loaders_lin_x86.tar.gz
    fi

    echo "Installing latest ionCube PHP loader..."
    run mv -f ioncube /usr/lib/php/loaders/
    run popd
}

# Enable ionCube Loader
function enable_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Enabling ionCube PHP${PHPv} loader"

    if "${DRYRUN}"; then
        warning "ionCube PHP${PHPv} enabled in dryrun mode."
    else
        if [ -f "/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so" ]; then
            cat > "/etc/php/${PHPv}/mods-available/ioncube.ini" <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
            fi

            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
            fi
        else
            warning "Sorry, no ionCube loader found for PHP${PHPv}"
        fi
    fi
}

# Disable ionCube Loader.
function disable_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Disabling ionCube PHP${PHPv} loader"

    run unlink "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
    run unlink "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
}

# Remove ionCube Loader.
function remove_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Uninstalling ionCube PHP${PHPv} loader..."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" || \
        -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]]; then
        disable_ioncube "${PHPv}"
    fi

    if [ -d /usr/lib/php/loaders/ioncube ]; then
        run rm -fr /usr/lib/php/loaders/ioncube
        status "ionCube PHP${PHPv} loader has been removed."
    else
        warning "ionCube PHP${PHPv} loader couldn't be found."
    fi
}

# Install SourceGuardian.
function install_sourceguardian() {
    echo "Installing SourceGuardian PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Removing old/existing loader..."
        run rm -fr /usr/lib/php/loaders/sourceguardian
    fi

    if [ ! -d "${BUILD_DIR}/sourceguardian" ]; then
        run mkdir -p "${BUILD_DIR}/sourceguardian"
    fi

    run pushd "${BUILD_DIR}/sourceguardian"

    ARCH=${ARCH:-$(uname -p)}
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
        run tar -xzf loaders.linux-x86_64.tar.gz
        run rm -f loaders.linux-x86_64.tar.gz
    else
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86.tar.gz"
        run tar -xzf loaders.linux-x86.tar.gz
        run rm -f loaders.linux-x86.tar.gz
    fi

    run popd

    echo "Installing latest SourceGuardian PHP loader..."
    run mv -f "${BUILD_DIR}/sourceguardian" /usr/lib/php/loaders/
}

# Enable SourceGuardian.
function enable_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Enabling SourceGuardian PHP${PHPv} loader..."

    if "${DRYRUN}"; then
        warning "SourceGuardian PHP${PHPv} enabled in dryrun mode."
    else
        if [ -f "/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin" ]; then
            cat > "/etc/php/${PHPv}/mods-available/sourceguardian.ini" <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
            fi

            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
            fi
        else
            warning "Sorry, no SourceGuardian loader found for PHP ${PHPv}"
        fi
    fi
}

# Disable SourceGuardian Loader.
function disable_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Disabling SourceGuardian PHP${PHPv} loader"

    run unlink "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
    run unlink "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
}

# Remove SourceGuardian Loader
function remove_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Uninstalling SourceGuardian PHP${PHPv} loader..."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" || \
        -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]]; then
        disable_sourceguardian "${PHPv}"
    fi

    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        run rm -fr /usr/lib/php/loaders/sourceguardian
        status "SourceGuardian PHP${PHPv} loader has been removed."
    else
        warning "SourceGuardian PHP${PHPv} loader couldn't be found."
    fi
}

# Phalcon Framework.
function install_phalcon() {
    local PHPv=${1:-$PHP_VERSION}

    # Install prerequisite packages.
    run apt-get install -y gcc libpcre3-dev make re2c autoconf automake

    # Install Zephir from source.
    while [[ $INSTALL_ZEPHIR != "y" && $INSTALL_ZEPHIR != "n" ]]; do
        read -rp "Install Zephir Interpreter? [y/n]: " -e INSTALL_ZEPHIR
    done

    if [[ "$INSTALL_ZEPHIR" == Y* || "$INSTALL_ZEPHIR" == y* ]]; then
        # Install Zephir parser.
        run git clone -q git://github.com/phalcon/php-zephir-parser.git "${BUILD_DIR}/php-zephir-parser"
        run pushd "${BUILD_DIR}/php-zephir-parser"

        if [[ -n "${PHPv}" ]]; then
            run "phpize${PHPv}"
            run ./configure --with-php-config="/usr/bin/php-config${PHPv}"
        else
            run phpize
            run ./configure
        fi

        run make
        run make install
        run popd

        # Install Zephir.
        ZEPHIR_BRANCH=$(git ls-remote https://github.com/phalcon/zephir 0.12.* | sort -t/ -k3 -Vr | head -n1 | awk -F/ '{ print $NF }')
        run git clone --depth 1 --branch "${ZEPHIR_BRANCH}" -q https://github.com/phalcon/zephir.git "${BUILD_DIR}/zephir"
        run pushd "${BUILD_DIR}/zephir"
        # install zephir
        run composer install
        run popd
    fi

    # Install cPhalcon from source.
    run git clone --depth=1 --branch=3.4.x -q https://github.com/phalcon/cphalcon.git "${BUILD_DIR}/cphalcon"
    run pushd "${BUILD_DIR}/cphalcon/build"

    if [[ -n "${PHPv}" ]]; then
        run ./install --phpize "/usr/bin/phpize${PHPv}" --php-config "/usr/bin/php-config${PHPv}"
    else
        run ./install
    fi

    run popd
}

# PHP & FPM Optimization.
function optimize_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo "Optimizing PHP${PHPv} & FPM configuration..."

    if [ ! -d "/etc/php/${PHPv}/fpm" ]; then
        run mkdir "/etc/php/${PHPv}/fpm"
    fi

    # Copy the optimized-version of php.ini
    if [ -f "etc/php/${PHPv}/fpm/php.ini" ]; then
        run mv "/etc/php/${PHPv}/fpm/php.ini" "/etc/php/${PHPv}/fpm/php.ini.old"
        run cp -f "etc/php/${PHPv}/fpm/php.ini" "/etc/php/${PHPv}/fpm/"
    else
        cat >> "/etc/php/${PHPv}/fpm/php.ini" <<EOL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Custom Optimization for LEMPer ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=5
opcache.validate_timestamps=1
opcache.revalidate_freq=1
opcache.save_comments=1
opcache.error_log="/var/log/php/php${PHPv}-opcache_error.log"

EOL
    fi

    # Copy the optimized-version of php-fpm config file.
    if [ -f "etc/php/${PHPv}/fpm/php-fpm.conf" ]; then
        run mv "/etc/php/${PHPv}/fpm/php-fpm.conf" "/etc/php/${PHPv}/fpm/php-fpm.conf.old"
        run cp -f "etc/php/${PHPv}/fpm/php-fpm.conf" "/etc/php/${PHPv}/fpm/"
    else
        if grep -qwE "^emergency_restart_threshold\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
            run sed -i "s/^emergency_restart_threshold\ =\ [0-9]*/emergency_restart_threshold\ =\ 10/g" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        else
            run sed -i "/^;emergency_restart_threshold/a emergency_restart_threshold\ =\ 10" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        fi

        if grep -qwE "^emergency_restart_interval\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
            run sed -i "s/^emergency_restart_interval\ =\ [0-9]*/emergency_restart_interval\ =\ 60/g" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        else
            run sed -i "/^;emergency_restart_interval/a emergency_restart_interval\ =\ 60" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        fi

        if grep -qwE "^process_control_timeout\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
            run sed -i "s/^process_control_timeout\ =\ [0-9]*/process_control_timeout\ =\ 10/g" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        else
            run sed -i "/^;process_control_timeout/a process_control_timeout\ =\ 10" \
                "/etc/php/${PHPv}/fpm/php-fpm.conf"
        fi
    fi

    if [ ! -d "/etc/php/${PHPv}/fpm/pool.d" ]; then
        run mkdir "/etc/php/${PHPv}/fpm/pool.d"
    fi

    # Copy the optimized-version of php fpm default pool
    if [ -f "etc/php/${PHPv}/fpm/pool.d/www.conf" ]; then
        run mv "/etc/php/${PHPv}/fpm/pool.d/www.conf" "/etc/php/${PHPv}/fpm/pool.d/www.conf.old"
        run cp -f "etc/php/${PHPv}/fpm/pool.d/www.conf" "/etc/php/${PHPv}/fpm/pool.d/"
    fi

    # Copy the optimized-version of php fpm lemper pool
    if [ -f "etc/php/${PHPv}/fpm/pool.d/lemper.conf" ]; then
        run mv "/etc/php/${PHPv}/fpm/pool.d/lemper.conf" "/etc/php/${PHPv}/fpm/pool.d/lemper.conf.old"
        run cp -f "etc/php/${PHPv}/fpm/pool.d/lemper.conf" "/etc/php/${PHPv}/fpm/pool.d/"
    else
        cat >> "/etc/php/${PHPv}/fpm/pool.d/lemper.conf" <<EOL
[lemper]
user = lemper
group = lemper

listen = /run/php/php${PHPv}-fpm.\$pool.sock
listen.owner = lemper
listen.group = lemper
listen.mode = 0666
;listen.allowed_clients = 127.1.0.1

; Custom PHP-FPM optimization
; adjust here to meet your needs.
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s
pm.max_requests = 500

pm.status_path = /status
ping.path = /ping

request_slowlog_timeout = 5s
slowlog = /var/log/php/php${PHPv}-fpm_slow.\$pool.log

chdir = /home/lemper

security.limit_extensions = .php .php3 .php4 .php5 .php${PHPv//./}

; Custom PHP ini settings.
php_flag[display_errors] = on
;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_admin_value[error_log] = /var/log/php/php${PHPv}-fpm.\$pool.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = 128M
php_admin_value[open_basedir] = /home/lemper

EOL
    fi

    # Fix cgi.fix_pathinfo (for PHP older than 5.3)
    #sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHPv}/fpm/php.ini

    # Add custom php extension (ex .php70, .php71)
    PHPExt=".php${PHPv//.}"
    run sed -i "s/;\(security\.limit_extensions\s*=\s*\).*$/\1\.php\ $PHPExt/" \
        "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Enable FPM ping service.
    run sed -i "/^;ping.path\ =.*/a ping.path\ =\ \/ping" "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Enable FPM status.
    run sed -i "/^;pm.status_path\ =.*/a pm.status_path\ =\ \/status" \
        "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Restart PHP-fpm server.
    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
        run service "php${PHPv}-fpm" reload
        status "PHP${PHPv}-FPM reloaded successfully."
    elif [[ -n $(command -v "php${PHPv}") ]]; then
        run service "php${PHPv}-fpm" start

        if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
            status "PHP${PHPv}-FPM started successfully."
        else
            warning "Something wrong with PHP${PHPv} & FPM installation."
        fi
    fi
}

# Start PHP & FPM Installation.
#
function init_php_fpm_install() {
    if "${AUTO_INSTALL}"; then
        SELECTED_PHP=${PHP_VERSION:-"7.3"}
    else
        echo "Which version of PHP to install?"
        echo "Supported PHP version:"
        echo "  1). PHP 5.6 (old stable)"
        echo "  2). PHP 7.0 (stable)"
        echo "  3). PHP 7.1 (stable)"
        echo "  4). PHP 7.2 (stable)"
        echo "  5). PHP 7.3 (latest stable)"
        echo "  6). All available versions"
        echo "---------------------------------"

        while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
                ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
                ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" ]]; do
            read -rp "Select an option [1-6]: " -i 5 -e SELECTED_PHP
        done

        echo ""
    fi

    local PHPv
    case ${SELECTED_PHP} in
        1|"5.6")
            PHPv="5.6"
            install_php_fpm "${PHPv}"
        ;;

        2|"7.0")
            PHPv="7.0"
            install_php_fpm "${PHPv}"
        ;;

        3|"7.1")
            PHPv="7.1"
            install_php_fpm "${PHPv}"
        ;;

        4|"7.2")
            PHPv="7.2"
            install_php_fpm "${PHPv}"
        ;;

        5|"7.3")
            PHPv="7.3"
            install_php_fpm "${PHPv}"
        ;;

        "all")
            PHPv="all"
            install_php_fpm "5.6"
            install_php_fpm "7.0"
            install_php_fpm "7.1"
            install_php_fpm "7.2"
            install_php_fpm "7.3"
        ;;

        *)
            PHPv="unsupported"
            warning "Your selected PHP version ${SELECTED_PHP} is not supported yet."
        ;;
    esac

    # Install default PHP version used by LEMPer.
    if [[ ! -n $(command -v php7.3) ]]; then
        warning -e "\nLEMPer requires PHP 7.3 as default to run its administration tools."
        echo "PHP 7.3 now being installed..."
        install_php_fpm "7.3"
    fi

    # Install PHP loader.
    if [[ "${PHPv}" != "unsupported" && "${PHP_IS_INSTALLED}" != "yes" ]]; then
        if "${AUTO_INSTALL}"; then
            if [[ -n "${PHP_LOADER}" ]]; then
                INSTALL_PHPLOADER="y"
                SELECTED_PHPLOADER=${PHP_LOADER}
            else
                INSTALL_PHPLOADER="n"
            fi
        else
            echo ""
            while [[ ${INSTALL_PHPLOADER} != "y" && ${INSTALL_PHPLOADER} != "n" ]]; do
                read -rp "Do you want to install PHP Loaders? [y/n]: " -e INSTALL_PHPLOADER
            done
        fi

        if [[ "${INSTALL_PHPLOADER}" == Y* || "${INSTALL_PHPLOADER}" == y* ]]; then
            echo ""
            echo "Available PHP Loaders:"
            echo "  1). ionCube Loader (latest stable)"
            echo "  2). SourceGuardian (latest stable)"
            echo "  3). All loaders (ionCube, SourceGuardian)"
            echo "--------------------------------------------"

            while [[ ${SELECTED_PHPLOADER} != "1" && ${SELECTED_PHPLOADER} != "2" && \
                    ${SELECTED_PHPLOADER} != "3" && ${SELECTED_PHPLOADER} != "ioncube" && \
                    ${SELECTED_PHPLOADER} != "sourceguardian" && ${SELECTED_PHPLOADER} != "all" ]]; do
                read -rp "Select an option [1-3]: " -i "${PHP_LOADER}" -e SELECTED_PHPLOADER
            done

            echo ""

            # Create loaders directory
            if [ ! -d /usr/lib/php/loaders ]; then
                run mkdir -p /usr/lib/php/loaders
            fi

            case ${SELECTED_PHPLOADER} in
                1|"ioncube")
                    install_ioncube

                    if [ "${PHPv}" != "all" ]; then
                        enable_ioncube "${PHPv}"

                        # Required for LEMPer default PHP
                        if [ "${PHPv}" != "7.3" ]; then
                            enable_ioncube "7.3"
                        fi
                    else
                        enable_ioncube "5.6"
                        enable_ioncube "7.0"
                        enable_ioncube "7.1"
                        enable_ioncube "7.2"
                        enable_ioncube "7.3"
                    fi
                ;;
                2|"sourceguardian")
                    install_sourceguardian

                    if [ "${PHPv}" != "all" ]; then
                        enable_sourceguardian "${PHPv}"
                    else
                        enable_sourceguardian "5.6"
                        enable_sourceguardian "7.0"
                        enable_sourceguardian "7.1"
                        enable_sourceguardian "7.2"
                        enable_sourceguardian "7.3"
                    fi
                ;;
                "all")
                    install_ioncube
                    install_sourceguardian

                    if [ "${PHPv}" != "all" ]; then
                        enable_ioncube "${PHPv}"

                        # Required for LEMPer default PHP
                        if [ "${PHPv}" != "7.3" ]; then
                            enable_ioncube "7.3"
                        fi

                        enable_sourceguardian "${PHPv}"
                    else
                        enable_ioncube "5.6"
                        enable_ioncube "7.0"
                        enable_ioncube "7.1"
                        enable_ioncube "7.2"
                        enable_ioncube "7.3"

                        enable_sourceguardian "5.6"
                        enable_sourceguardian "7.0"
                        enable_sourceguardian "7.1"
                        enable_sourceguardian "7.2"
                        enable_sourceguardian "7.3"
                    fi
                ;;

                *)
                    warning "Your selected PHP loader ${SELECTED_PHPLOADER} is not supported yet."
                ;;
            esac
        fi

        # Install Phalcon PHP Framework.
        if "${AUTO_INSTALL}"; then
            INSTALL_PHALCON="y"
        else
            echo ""
            while [[ ${INSTALL_PHALCON} != "y" && ${INSTALL_PHALCON} != "n" ]]; do
                read -rp "Do you want to install Phalcon framework? [y/n]: " -e INSTALL_PHALCON
            done
        fi

        SELECTED_PHALCON=${PHP_PHALCON_INSTALLER:-"source"}
        if [[ "${INSTALL_PHALCON}" == Y* || "${INSTALL_PHALCON}" == y* ]]; then
            echo ""
            echo "Available Phalcon framework installer:"
            echo "  1). Repository (repo)"
            echo "  2). Source (source)"
            echo "--------------------------------------------"

            while [[ ${SELECTED_PHALCON} != "1" && ${SELECTED_PHALCON} != "2" && \
                    ${SELECTED_PHALCON} != "repo" && ${SELECTED_PHALCON} != "source" ]]; do
                read -rp "Select an option [1-2]: " -e SELECTED_PHALCON
            done

            echo ""

            case ${SELECTED_PHALCON} in
                1|"source")
                    run install_phalcon "${PHPv}"
                ;;
                2|"repo"|*)
                    run apt-get install -y php-phalcon
                ;;
            esac
        fi

        # Final optimization.
        if "${DRYRUN}"; then
            warning "PHP${PHPv} & FPM installed and optimized in dryrun mode."
        else
            if [ "${PHPv}" != "all" ]; then
                optimize_php_fpm "${PHPv}"

                # Required for LEMPer default PHP
                if [ "${PHPv}" != "7.3" ]; then
                    optimize_php_fpm "7.3"
                fi
            else
                optimize_php_fpm "5.6"
                optimize_php_fpm "7.0"
                optimize_php_fpm "7.1"
                optimize_php_fpm "7.2"
                optimize_php_fpm "7.3"
            fi
        fi
    fi
}

echo "[Welcome to PHP Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v php5.6) && \
    -n $(command -v php7.0) && \
    -n $(command -v php7.1) && \
    -n $(command -v php7.2) && \
    -n $(command -v php7.3) ]]; then
    warning "All available PHP version already exists. Installation skipped..."
else
    init_php_fpm_install "$@"
fi
