#!/usr/bin/env bash

# MariaDB Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 13/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

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
# Add MariaDB Repository.
##
function add_mariadb_repo() {
    echo "Adding MariaDB repository..."

    MYSQL_SERVER=${MYSQL_SERVER:-"mariadb"}
    MYSQL_VERSION=${MYSQL_VERSION:-"12.3"}

    # Fallback to oldest version if OS release is not supported.
    case "${RELEASE_NAME}" in
        jessie)
            MYSQL_VERSION="10.5"
        ;;
        bionic)
           MYSQL_VERSION="11.1"
        ;;
    esac

    # Add a MariaDB APT repository using a dedicated keyring with signed-by.
    # APT verifies the Release file signature against the keyring, so no
    # remote setup script is ever downloaded and executed (the previous
    # mariadb_repo_setup flow ran an unverified script as root).
    add_mariadb_repo() {
        local MARIADB_REPO_URL="${1}"
        local MARIADB_KEYRING="/usr/share/keyrings/mariadb-keyring.gpg"

        if curl -sLI "${MARIADB_REPO_URL}/dists/${RELEASE_NAME}/Release" | grep -q "HTTP/[.12]* [2].."; then
            run bash -c "curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | gpg --dearmor --yes -o ${MARIADB_KEYRING}" && \
            run chmod 644 "${MARIADB_KEYRING}" && \
            printf '%s\n' "deb [signed-by=${MARIADB_KEYRING}] ${MARIADB_REPO_URL} ${RELEASE_NAME} main" | \
                run tee /etc/apt/sources.list.d/mariadb.list > /dev/null && \
            printf '%s\n' "#deb-src [signed-by=${MARIADB_KEYRING}] ${MARIADB_REPO_URL} ${RELEASE_NAME} main" | \
                run tee -a /etc/apt/sources.list.d/mariadb.list > /dev/null && \
            run apt-get update --allow-releaseinfo-change -q -y
        else
            error "MariaDB ${MYSQL_VERSION} release at ${MARIADB_REPO_URL} not found."
        fi
    }

    if [[ "${MYSQL_REPO_MIRROR_URL}x" == "x" ]]; then
        # Add MariaDB official repo. mirror.mariadb.org redirects to a nearby
        # mirror; APT still verifies the Release signature via the keyring.
        add_mariadb_repo "https://mirror.mariadb.org/repo/${MYSQL_VERSION}/${DISTRIB_NAME}"
    else
        # Add MariaDB mirror repo.
        add_mariadb_repo "${MYSQL_REPO_MIRROR_URL}/repo/${MYSQL_VERSION}/${DISTRIB_NAME}"
    fi
}

##
# Install MariaDB (MySQL drop-in).
##
function init_mariadb_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MYSQL}" == true ]]; then
            DO_INSTALL_MYSQL="y"
        else
            DO_INSTALL_MYSQL="n"
        fi
    else
        while [[ "${DO_INSTALL_MYSQL}" != y* && "${DO_INSTALL_MYSQL}" != n* ]]; do
            read -rp "Do you want to install MariaDB server? [y/n]: " -i y -e DO_INSTALL_MYSQL
        done
    fi

    # Do MariaDB server installation here...
    if [[ ${DO_INSTALL_MYSQL} == y* || ${DO_INSTALL_MYSQL} == Y* ]]; then
        # Add repository.
        add_mariadb_repo

        echo "Installing MariaDB (MySQL drop-in replacement) server..."

        # Install MariaDB
        run apt-get install -q -y libmariadb-dev libmariadb3 libmariadbclient18 mariadb-client mariadb-client-core \
            mariadb-common mariadb-server mariadb-server-core mariadb-backup

        # Configure MySQL installation.
        if [[ "${DRYRUN}" == true ]]; then
            info "MariaDB server installed in dry run mode."
        else
            if [[ -n $(command -v mysql) ]]; then
                if [[ ! -d /etc/mysql/conf.d ]]; then
                    run mkdir -p /etc/mysql/conf.d
                    run cp -fr etc/mysql/conf.d /etc/mysql/
                fi

                if [[ ! -d /etc/mysql/mariadb.conf.d ]]; then
                    run mkdir -p /etc/mysql/mariadb.conf.d
                    run cp -fr etc/mysql/mariadb.conf.d /etc/mysql/
                fi

                [[ ! -f /etc/mysql/mariadb.cnf ]] && run cp -f etc/mysql/mariadb.cnf /etc/mysql/
                [[ ! -f /etc/mysql/my.cnf ]] && run ln -s /etc/mysql/mariadb.cnf /etc/mysql/my.cnf
                [[ ! -f /etc/mysql/debian.cnf ]] && run cp -f etc/mysql/debian.cnf /etc/mysql/

                # Debian start service.
                if [[ ! -f /etc/mysql/debian-start || "${MYSQL_SECURE_INSTALL}" == true ]]; then
                    run cp -f etc/mysql/debian-start /etc/mysql/
                    run chmod ugo+x /etc/mysql/debian-start
                fi

                # MySQL init script.
                if [[ ! -f /etc/init.d/mysql ]]; then
                    run cp etc/init.d/mysql /etc/init.d/
                    run chmod ugo+x /etc/init.d/mysql
                fi

                # MariaDB init script.
                if [[ ! -f /etc/init.d/mariadb ]]; then
                    run cp etc/init.d/mariadb /etc/init.d/
                    run chmod ugo+x /etc/init.d/mariadb
                fi

                # Systemd script.
                [[ ! -f /lib/systemd/system/mariadb.service ]] && \
                    run cp etc/systemd/mariadb.service /lib/systemd/system/

                [[ ! -f /etc/systemd/system/multi-user.target.wants/mariadb.service && -f /lib/systemd/system/mariadb.service ]] && \
                    run ln -sf /lib/systemd/system/mariadb.service /etc/systemd/system/multi-user.target.wants/mariadb.service

                [[ ! -f /etc/systemd/system/mysqld.service && -f /lib/systemd/system/mariadb.service ]] && \
                    run ln -sf /lib/systemd/system/mariadb.service /etc/systemd/system/mysqld.service

                [[ ! -f /etc/systemd/system/mysql.service && -f /lib/systemd/system/mariadb.service ]] && \
                    run ln -sf /lib/systemd/system/mariadb.service /etc/systemd/system/mysql.service

                # Install default table.
                if [[ -n $(command -v mariadb-install-db) ]]; then
                    run mariadb-install-db && \
                    run chown -hR mysql:mysql /var/lib/mysql
                elif [[ -n $(command -v mysql_install_db) ]]; then
                    run mysql_install_db && \
                    run chown -hR mysql:mysql /var/lib/mysql
                else
                    error "Unable to secure MariaDB installation."
                fi

                # Trying to reload daemon.
                run systemctl daemon-reload

                # Unmask systemd service (?)
                run systemctl unmask mariadb.service

                # Enable MariaDB on startup.
                run systemctl enable mariadb.service

                # Restart MariaDB service daemon.
                run systemctl start mariadb.service

                ##
                # MariaDB secure installation
                # Ref: https://mariadb.com/kb/en/library/security-of-mariadb-root-account/
                #
                if [[ "${AUTO_INSTALL}" == true ]]; then
                    if [[ "${MYSQL_SECURE_INSTALL}" == true ]]; then
                        echo "Securing MariaDB Installation..."

                        # Ref: https://bertvv.github.io/notes-to-self/2015/11/16/automating-mysql_secure_installation/
                        MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
                        local SQL_QUERY=""

                        # Setting the database root password.
                        SQL_QUERY="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"

                        # Delete anonymous users.
                        SQL_QUERY="${SQL_QUERY}
                                DELETE FROM mysql.user WHERE User='';"
                        
                        # Ensure the root user can not log in remotely.
                        SQL_QUERY="${SQL_QUERY}
                                DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"

                        # Remove the test database.
                        SQL_QUERY="${SQL_QUERY}
                                DROP DATABASE IF EXISTS test;
                                DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"

                        # Flush the privileges tables.
                        SQL_QUERY="${SQL_QUERY}
                                FLUSH PRIVILEGES;"

                        # Root password is blank for newly installed MariaDB (MySQL).
                        # mysql_root uses MYSQL_PWD so the password never appears in argv.
                        if mysql_root -e "${SQL_QUERY}"; then
                            success "Securing MariaDB server installation has been done."
                        else
                            error "Unable to secure MariaDB server installation."
                        fi
                    fi
                else
                    if [[ "${MYSQL_SECURE_INSTALL}" == true ]]; then
                        while [[ "${DO_MYSQL_SECURE_INSTALL}" != "y" && "${DO_MYSQL_SECURE_INSTALL}" != "n" ]]; do
                            read -rp "Do you want to secure MariaDB installation? [y/n]: " -e DO_MYSQL_SECURE_INSTALL
                        done

                        if [[ "${DO_MYSQL_SECURE_INSTALL}" == y* || "${DO_MYSQL_SECURE_INSTALL}" == Y* ]]; then
                            if [[ -n $(command -v mariadb-secure-installation) ]]; then
                                run mariadb-secure-installation
                            elif [[ -n $(command -v mysql_secure_installation) ]]; then
                                run mysql_secure_installation
                            else
                                error "Unable to secure MariaDB installation."
                            fi
                        fi
                    fi
                fi
            fi

            if [[ $(pgrep -c mariadb) -gt 0 || -n $(command -v mysql) ]]; then
                success "MariaDB server installed successfully."

                # Allow remote client access
                allow_remote_client_access

                # Enable Mariabackup
                enable_mariabackup

                # Restart MariaDB (MySQL)
                run systemctl restart mariadb.service

                if [[ $(pgrep -c mariadb) -gt 0 ]]; then
                    success "MariaDB server configured successfully."
                elif [[ -n $(command -v mysql) || -n $(command -v mariadb) ]]; then
                    # Server died? try to start it.
                    run systemctl start mariadb.service

                    if [[ $(pgrep -c mariadb) -gt 0 ]]; then
                        success "MariaDB server configured successfully."
                    else
                        info "Something went wrong with MariaDB server configuration."
                    fi
                fi
            else
                info "Something went wrong with MariaDB server installation."
            fi
        fi
    else
        info "MariaDB installation skipped."
    fi
}

##
# Enable MariaDB Backup tool.
##
function enable_mariabackup() {
    echo ""
    echo "Mariabackup will be installed and enabled by default."
    echo "It is useful to backup and restore MySQL database."
    echo ""
    sleep 1

    export MARIABACKUP_USER=${MARIABACKUP_USER:-"lemperdb"}
    MARIABACKUP_PASS=${MARIABACKUP_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
    export MARIABACKUP_PASS

    #echo "Please enter your current MySQL root password to process!"
    until [[ "${MYSQL_ROOT_PASSWORD}" != "" ]]; do
        echo -n "MySQL root password: "; stty -echo; read -r MYSQL_ROOT_PASSWORD; stty echo; echo
    done
    export MYSQL_ROOT_PASSWORD

    # Create default LEMPer database user if not exists.
    if ! mysql_root -e "SELECT User FROM mysql.user;" | grep -q "${MARIABACKUP_USER}"; then
        # Create mariabackup user.
        SQL_QUERY="CREATE USER '${MARIABACKUP_USER}'@'localhost' IDENTIFIED BY '${MARIABACKUP_PASS}';
                GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO '${MARIABACKUP_USER}'@'localhost';"

        run mysql_root -e "${SQL_QUERY}"

        # Update my.cnf
        MARIABACKUP_CNF="###################################
# Custom optimization for LEMPer
# Mariabackup credential
#
[mariabackup]
user=${MARIABACKUP_USER}
password=${MARIABACKUP_PASS}
open_files_limit=65535
"

        # Write the credential file with root-only permissions and without
        # `bash -c` interpolation of the password.
        run mkdir -p /etc/mysql/mariadb.conf.d
        printf '%s\n' "${MARIABACKUP_CNF}" | run tee /etc/mysql/mariadb.conf.d/50-mariabackup.cnf > /dev/null
        run chmod 0600 /etc/mysql/mariadb.conf.d/50-mariabackup.cnf

        # Save config.
        save_config -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}\nMARIABACKUP_USERNAME=${MARIABACKUP_USER}\nMARIABACKUP_PASSWORD=${MARIABACKUP_PASS}"

        # Save log (no plaintext secrets: credentials live in /etc/lemper/lemper.conf, 0600).
        save_log -e "MariaDB server credentials generated.\nMariaBackup DB user: ${MARIABACKUP_USER}\nAll credentials stored in /etc/lemper/lemper.conf (mode 0600, root-only)."
    else
        info "It seems that user '${MARIABACKUP_USER}' already exists. You can add mariabackup user manually!"
    fi
}

##
# Allow remote client access
# You need to add the following query to the client account
#CREATE USER 'username'@'ip_address' IDENTIFIED BY 'secret';
#GRANT ALL PRIVILEGES ON *.* TO 'username'@'ip_address' WITH GRANT OPTION;
#CREATE USER 'username'@'%' IDENTIFIED BY 'secret';
#GRANT ALL PRIVILEGES ON *.* TO 'usernemae'@'%' WITH GRANT OPTION;
#FLUSH PRIVILEGES;
##
function allow_remote_client_access() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if "${MYSQL_ALLOW_REMOTE}"; then
            ENABLE_REMOTE_ACCESS="y"
        else
            ENABLE_REMOTE_ACCESS="n"
        fi
    else
        while [[ "${ENABLE_REMOTE_ACCESS}" != "y" && "${ENABLE_REMOTE_ACCESS}" != "n" ]]; do
            read -rp "Do you want to allow MySQL remote client access? [y/n]: " -e ENABLE_REMOTE_ACCESS
        done
    fi

    if [[ ${ENABLE_REMOTE_ACCESS} == y* ]]; then
        REMOTE_CLIENT_CNF="###################################
# Custom optimization for LEMPer
# Allow remote client access
#
[mysqld]
skip-networking=0
skip-bind-address"

        if [[ -d /etc/mysql/mariadb.conf.d ]]; then
            run touch /etc/mysql/mariadb.conf.d/20-allow-remote-client-access.cnf
            run bash -c "echo '${REMOTE_CLIENT_CNF}' > /etc/mysql/mariadb.conf.d/20-allow-remote-client-access.cnf"
        else
            run bash -c "echo -e '\n${REMOTE_CLIENT_CNF}' >> /etc/mysql/my.cnf"
        fi
    fi
}

echo "[MariaDB (MySQL drop-in replacement) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mariadb) && -n $(command -v mariadbd) && "${FORCE_INSTALL}" != true ]]; then
    info "MariaDB server already exists, installation skipped."
else
    init_mariadb_install "$@"
fi
