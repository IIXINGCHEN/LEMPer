#!/usr/bin/env bash

# MongoDB installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
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

# Set MongoDB version.
case "${RELEASE_NAME}" in
    bookworm)
        MONGODB_VERSION="8.0"
    ;;
    jammy)
        if version_older_than "${MONGODB_VERSION}" "8.0"; then
            MONGODB_VERSION="8.0"
        fi
    ;;
    *)
        MONGODB_VERSION=${MONGODB_VERSION:-"8.0"}
    ;;
esac

##
# Add MongoDB repository.
##
function add_mongodb_repo() {
    case "${DISTRIB_NAME}" in
        debian)
            if [[ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]]; then
                echo "Adding MongoDB repository..."

                run bash -c "curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg" && \
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg] ${MONGODB_REPO_BASE:-https://repo.mongodb.org/apt}/debian ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} main' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" && \
                run apt-get update -q -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]]; then
                echo "Adding MongoDB repository..."

                run bash -c "curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | gpg --dearmor --yes -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg" && \
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" && \
                run bash -c "echo 'deb [signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg] ${MONGODB_REPO_BASE:-https://repo.mongodb.org/apt}/ubuntu ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} multiverse' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" && \
                run apt-get update -q -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        *)
            error "Unable to add MongoDB repo, unsupported release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

##
# Initialize MongoDB Installation.
##
function init_mongodb_install() {
    #local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MONGODB}" == true ]]; then
            DO_INSTALL_MONGODB="y"
            #SELECTED_INSTALLER=${MONGODB_INSTALLER:-"repo"}
        else
            DO_INSTALL_MONGODB="n"
        fi
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to install MongoDB server? [y/n]: " -i y -e DO_INSTALL_MONGODB
        done
    fi

    if [[ ${DO_INSTALL_MONGODB} == y* || ${DO_INSTALL_MONGODB} == Y* ]]; then
        # Add repository.
        add_mongodb_repo

        echo "Installing MongoDB server..."

        # Ubuntu 24.04 (Noble) uses t64 library package names.
        local MONGODB_LIBS="libbson-1.0 libmongoc-1.0-0"
        if [[ "${DISTRIB_NAME}" == "ubuntu" && "${RELEASE_NAME}" == "noble" ]]; then
            MONGODB_LIBS="libbson-1.0-0t64 libmongoc-1.0-0t64"
        fi

        run apt-get install -q -y ${MONGODB_LIBS} mongodb-org mongodb-org-server \
            mongodb-org-shell mongodb-org-tools mongodb-org-mongos mongodb-database-tools \
            mongodb-org-database-tools-extra mongodb-mongosh

        if [[ "${DRYRUN}" != true ]]; then
            # Enable in start-up.
            echo "Enable MongoDB systemd service..."

            run systemctl start mongod.service
            run systemctl enable mongod

            if [[ $(systemctl is-active mongod) == 'active' ]]; then
                echo "MongoDB server is running."
            else
                echo "MongoDB server is not running."
            fi

            # Add MongoDB default admin user.
            if [[ -n $(command -v mongosh) && $(pgrep -c mongod) -gt 0 ]]; then
                echo "Final test MongoDB service..."

                sleep 3 # Wait for MongoDB to completely started.

                export MONGODB_ADMIN_USER=${MONGODB_ADMIN_USER:-"lemperdb"}
                export MONGODB_ADMIN_PASSWORD=${MONGODB_ADMIN_PASSWORD:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

                # Create the admin user via a 0600 temp JS file, so the password
                # never appears in the process argument list.
                local MONGO_JS && MONGO_JS=$(mktemp /tmp/lemper-mongo.XXXXXX.js)
                chmod 0600 "${MONGO_JS}"
                # Escape backslashes and double quotes for the JS string literal.
                local _muser=${MONGODB_ADMIN_USER//\\/\\\\}
                local _mpass=${MONGODB_ADMIN_PASSWORD//\\/\\\\}
                _muser=${_muser//\"/\\\"}
                _mpass=${_mpass//\"/\\\"}
                printf 'db.createUser({user: "%s", pwd: "%s", roles: [{role: "root", db: "admin"}]});\n' \
                    "${_muser}" "${_mpass}" > "${MONGO_JS}"

                run mongosh admin "${MONGO_JS}"
                run rm -f "${MONGO_JS}"

                # Enable access control now that the admin user exists.
                # Without authorization, any local user can connect without credentials.
                if [[ "${DRYRUN}" != true && -f /etc/mongod.conf ]]; then
                    if grep -qE '^[[:space:]]*authorization:[[:space:]]*enabled' /etc/mongod.conf; then
                        info "MongoDB authorization already enabled."
                    else
                        awk '
                            /^[[:space:]]*authorization:/ { next }
                            { print }
                            /^security:/ { print "  authorization: enabled"; added=1 }
                            END { if (!added) { print ""; print "security:"; print "  authorization: enabled" } }
                        ' /etc/mongod.conf > /etc/mongod.conf.new && \
                        mv /etc/mongod.conf.new /etc/mongod.conf && \
                        chmod 0600 /etc/mongod.conf
                        echo "Enabled MongoDB authorization in /etc/mongod.conf; restarting mongod..."
                        systemctl restart mongod
                    fi
                fi

                # Save config.
                save_config -e "MONGODB_HOST=127.0.0.1\nMONGODB_PORT=27017\nMONGODB_ADMIN_USER=${MONGODB_ADMIN_USER}\nMONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASSWORD}"

                # Save log.
                # Save log (no plaintext secrets: credentials live in /etc/lemper/lemper.conf, 0600).
                save_log -e "MongoDB default admin user '${MONGODB_ADMIN_USER}' created.\nCredentials stored in /etc/lemper/lemper.conf (mode 0600, root-only)."
            else
                echo "MongoDB installation completed with errors on start-up, please check the log file."
                echo -e "After installation finished, you can add a MongoDB administrative user.\nExample command lines below:";
                cat <<- EOL

mongosh
> use admin
> db.createUser({"user": "admin", "pwd": "<Enter a secure password>", "roles":[{"role": "root", "db": "admin"}]})
> quit()

mongosh -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {"capped": false})
> var a = {"name": "John Doe", "attributes": {"age": 30, "address": "123 Main St", "phone": 8675309}}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})

EOL
            fi
        else
            info "MongoDB server installed in dry run mode."
        fi
    else
        info "MongoDB server installation skipped."
    fi
}

echo "[MongoDB ${MONGODB_VERSION} Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mongod) && "${FORCE_INSTALL}" != true ]]; then
    info "MongoDB server already exists, installation skipped."
else
    init_mongodb_install "$@"
fi
