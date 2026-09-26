#!/usr/bin/env bash

# Install Monit (server monitoring)
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
# Install Monit.
##
function init_monit_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MONIT}" == true ]]; then
            DO_INSTALL_MONIT="y"
        else
            DO_INSTALL_MONIT="n"
        fi
    else
        while [[ "${DO_INSTALL_MONIT}" != y* && "${DO_INSTALL_MONIT}" != n* ]]; do
            read -rp "Do you want to install Monit server monitoring? [y/n]: " -i y -e DO_INSTALL_MONIT
        done
    fi

    if [[ ${DO_INSTALL_MONIT} == y* || ${DO_INSTALL_MONIT} == Y* ]]; then
        echo "Installing Monit from repository..."
        run apt-get install -q -y monit

        # Configure Monit.
        echo "Configuring Monit..."

        if [[ "${DRYRUN}" != true ]]; then
            local MONIT_CONF_DIR="/etc/monit/conf.d"
            local MONIT_LEMPER_CONF="${MONIT_CONF_DIR}/lemper"
            local POOLNAME=${LEMPER_USERNAME:-"lemper"}
            local MONIT_HOSTNAME=${HOSTNAME:-"localhost"}

            run mkdir -p "${MONIT_CONF_DIR}"

            {
                echo "# LEMPer Monit configuration."
                echo "# Managed by the LEMPer installer, manual changes will be overwritten."
                echo ""
                echo "# Mail alerts require a working MTA (see scripts/install_mailer.sh)."
                echo "set mailserver localhost"
                if [[ -n "${LEMPER_ADMIN_EMAIL}" ]]; then
                    echo "set alert ${LEMPER_ADMIN_EMAIL}"
                fi
                echo ""
                echo "# System resource checks."
                echo "check system ${MONIT_HOSTNAME}"
                echo "    if cpu usage > 80% for 5 cycles then alert"
                echo "    if memory usage > 85% for 5 cycles then alert"
                echo "    if loadavg (15min) > 4 for 5 cycles then alert"
                echo ""
                echo "check filesystem rootfs with path /"
                echo "    if space usage > 85% for 5 cycles then alert"
                echo "    if inode usage > 85% for 5 cycles then alert"
                echo ""
                echo "# Nginx web server."
                echo "check process nginx with pidfile /run/nginx.pid"
                echo "    start program = \"/usr/bin/systemctl start nginx\""
                echo "    stop program  = \"/usr/bin/systemctl stop nginx\""
                echo "    if failed port 80 protocol http then restart"
                echo "    if failed port 443 then alert"
                echo "    if 3 restarts within 5 cycles then timeout"
                echo ""

                # PHP-FPM pool per installed PHP version.
                local PHPv
                for PHPv in ${PHP_VERSIONS:-"8.4"}; do
                    echo "# PHP ${PHPv} FPM."
                    echo "check process php${PHPv}-fpm with pidfile /run/php/php${PHPv}-fpm.pid"
                    echo "    start program = \"/usr/bin/systemctl start php${PHPv}-fpm\""
                    echo "    stop program  = \"/usr/bin/systemctl stop php${PHPv}-fpm\""
                    echo "    if failed unixsocket /run/php/php${PHPv}-fpm.${POOLNAME}.sock then restart"
                    echo "    if 3 restarts within 5 cycles then timeout"
                    echo ""
                done

                echo "# MariaDB/MySQL database server."
                echo "check process mariadb with pidfile /run/mysqld/mysqld.pid"
                echo "    start program = \"/usr/bin/systemctl start mariadb\""
                echo "    stop program  = \"/usr/bin/systemctl stop mariadb\""
                echo "    if failed port 3306 protocol mysql then restart"
                echo "    if 3 restarts within 5 cycles then timeout"
                echo ""

                # Redis server, only when installed.
                if [[ "${INSTALL_REDIS}" == true ]]; then
                    echo "# Redis server."
                    echo "check process redis with pidfile /run/redis/redis-server.pid"
                    echo "    start program = \"/usr/bin/systemctl start redis-server\""
                    echo "    stop program  = \"/usr/bin/systemctl stop redis-server\""
                    echo "    if failed port 6379 then restart"
                    echo "    if 3 restarts within 5 cycles then timeout"
                    echo ""
                fi
            } > "${MONIT_LEMPER_CONF}"

            run chmod 600 "${MONIT_LEMPER_CONF}"
        fi

        # Validate Monit configuration syntax before (re)starting the daemon.
        echo "Validating Monit configuration..."
        run monit -t

        # Allow Monit to start on Debian/Ubuntu (disabled by default in /etc/default/monit).
        if [[ -f /etc/default/monit ]]; then
            run sed -i -e "s/^#*startup=.*/startup=1/" /etc/default/monit
            run bash -c "grep -q '^startup=1' /etc/default/monit || echo 'startup=1' >> /etc/default/monit"
        fi

        # Restart Monit daemon.
        echo "Starting Monit daemon..."
        run systemctl restart monit && \
        run systemctl enable monit

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c monit) -gt 0 ]]; then
                success "Monit installed successfully."
            else
                info "Something went wrong with Monit installation."
            fi
        else
            info "Monit installed in dry run mode."
        fi
    else
        info "Monit installation skipped."
    fi
}

echo "[Monit Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v monit) && -f /etc/monit/conf.d/lemper && "${FORCE_INSTALL}" != true ]]; then
    info "Monit already configured, installation skipped."
else
    init_monit_install "$@"
fi
