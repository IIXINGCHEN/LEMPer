#!/usr/bin/env bash

# Install Jailkit (chrooted SFTP jail)
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.2.0
#
# Jailkit provides a chroot jail so SFTP users can be confined to a limited
# filesystem (e.g. their web root) instead of seeing the whole server.
#
# Usage:
#   Set INSTALL_JAILKIT=true in .env (default false) and run install.sh, or
#   run this script directly as root. It installs jailkit from the distro
#   repository, initializes a base jail skeleton at /home/jail (override with
#   JAILKIT_JAIL_ROOT), and installs /usr/local/bin/lemper-jail-user.
#
# Jailing an existing user for SFTP-only access:
#   1. Create the user (if it does not exist yet):
#        adduser --disabled-password --gecos "" sftpuser
#   2. Move the user into the jail and restrict its login shell to jk_lsh:
#        sudo lemper-jail-user sftpuser
#   3. (Recommended) Force SFTP-only access in /etc/ssh/sshd_config:
#        Match User sftpuser
#            ChrootDirectory /home/jail
#            ForceCommand internal-sftp
#            AllowTCPForwarding no
#            X11Forwarding no
#      then: systemctl reload sshd
#
# Environment:
#   INSTALL_JAILKIT    - true to install (default: false).
#   JAILKIT_JAIL_ROOT  - jail directory (default: /home/jail).

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
# Install Jailkit and initialize the base chroot jail.
##
function init_jailkit_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_JAILKIT}" == true ]]; then
            DO_INSTALL_JAILKIT="y"
        else
            DO_INSTALL_JAILKIT="n"
        fi
    else
        while [[ "${DO_INSTALL_JAILKIT}" != "y" && "${DO_INSTALL_JAILKIT}" != "Y" && \
            "${DO_INSTALL_JAILKIT}" != "n" && "${DO_INSTALL_JAILKIT}" != "N" ]]; do
            read -rp "Do you want to install jailkit (chrooted SFTP jail)? [y/n]: " -e DO_INSTALL_JAILKIT
        done
    fi

    if [[ ${DO_INSTALL_JAILKIT} == y* || ${DO_INSTALL_JAILKIT} == Y* ]]; then
        echo "Installing Jailkit from repository..."
        run apt-get install -q -y jailkit

        local JAIL_ROOT="${JAILKIT_JAIL_ROOT:-/home/jail}"
        local JAIL_SECTIONS="basicshell"
        local JK_LSH=""

        # Initialize the base jail skeleton (idempotent: skip if already done).
        # The 'sftp' profile does not ship jk_lsh, so check for the jail's
        # core structure (populated by any jk_init section) instead.
        if [[ ! -d "${JAIL_ROOT}/usr" || ! -d "${JAIL_ROOT}/etc" ]]; then
            echo "Initializing chroot jail at ${JAIL_ROOT}..."

            # jk_init requires the jail directory to exist; create it first.
            # Must be 0755 (not group/other-writable) or jk_init refuses.
            run mkdir -p "${JAIL_ROOT}"
            run chmod 755 "${JAIL_ROOT}"

            # Prefer the 'sftp' profile from /etc/jailkit/jk_init.ini when the
            # distro package ships it; fall back to the minimal 'basicshell'.
            if [[ -f /etc/jailkit/jk_init.ini ]] && \
                grep -qE '^[[:space:]]*\[[[:space:]]*sftp[[:space:]]*\]' /etc/jailkit/jk_init.ini; then
                JAIL_SECTIONS="sftp"
            fi

            run jk_init -j "${JAIL_ROOT}" "${JAIL_SECTIONS}"
        else
            info "Chroot jail at ${JAIL_ROOT} already initialized, skipping."
        fi

        # Register jk_lsh as a valid login shell (idempotent).
        JK_LSH="$(command -v jk_lsh || true)"
        if [[ -n "${JK_LSH}" ]] && [[ "${DRYRUN}" != true ]]; then
            if ! grep -qxF "${JK_LSH}" /etc/shells 2>/dev/null; then
                echo "${JK_LSH}" >> /etc/shells
            fi
        fi

        # Install the jail user helper script.
        if [[ "${DRYRUN}" != true ]]; then
            echo "Installing lemper-jail-user helper..."
            cat > /usr/local/bin/lemper-jail-user <<'HELPER_EOF'
#!/usr/bin/env bash
#
# lemper-jail-user - Move an existing local user into the LEMPer jailkit
# chroot jail and restrict its login shell to jk_lsh.
#
# Usage:
#   sudo lemper-jail-user <username>
#
# What it does:
#   1. Moves <username>'s home directory into the jail with jk_jailuser.
#   2. Sets the user's login shell to jk_lsh (the limited jailkit shell).
#
# Typical SFTP-only workflow after jailing a user:
#   Add to /etc/ssh/sshd_config, then 'systemctl reload sshd':
#     Match User <username>
#         ChrootDirectory /home/jail
#         ForceCommand internal-sftp
#         AllowTCPForwarding no
#         X11Forwarding no
#
# Environment:
#   JAILKIT_JAIL_ROOT - jail directory (default: /home/jail)

JAIL_ROOT="${JAILKIT_JAIL_ROOT:-/home/jail}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: this script must be run as root." >&2
    exit 1
fi

USERNAME="${1:-}"
if [[ -z "${USERNAME}" ]]; then
    echo "Usage: $(basename "$0") <username>" >&2
    exit 1
fi

if ! id "${USERNAME}" >/dev/null 2>&1; then
    echo "Error: user '${USERNAME}' does not exist." >&2
    exit 1
fi

for cmd in jk_jailuser jk_lsh; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Error: '${cmd}' not found. Install jailkit first (scripts/install_jailkit.sh)." >&2
        exit 1
    fi
done

if [[ ! -d "${JAIL_ROOT}" ]]; then
    echo "Error: jail directory '${JAIL_ROOT}' not found. Run scripts/install_jailkit.sh first." >&2
    exit 1
fi

USER_HOME="$(getent passwd "${USERNAME}" | cut -d: -f6)"
if [[ "${USER_HOME}" == "${JAIL_ROOT}"* ]]; then
    echo "User '${USERNAME}' is already jailed in ${JAIL_ROOT}."
else
    echo "Moving user '${USERNAME}' into jail ${JAIL_ROOT}..."
    jk_jailuser -j "${JAIL_ROOT}" "${USERNAME}"
fi

JK_LSH="$(command -v jk_lsh)"
if [[ "$(getent passwd "${USERNAME}" | cut -d: -f7)" != "${JK_LSH}" ]]; then
    echo "Setting login shell of '${USERNAME}' to ${JK_LSH}..."
    usermod -s "${JK_LSH}" "${USERNAME}"
else
    echo "Login shell of '${USERNAME}' is already ${JK_LSH}."
fi

echo "Done. User '${USERNAME}' is now confined to ${JAIL_ROOT}."
echo "Tip: add an sshd 'Match User ${USERNAME}' block (ChrootDirectory ${JAIL_ROOT}, ForceCommand internal-sftp) to /etc/ssh/sshd_config for SFTP-only access."
HELPER_EOF
            run chmod 0755 /usr/local/bin/lemper-jail-user
        fi

        # Final test.
        if [[ "${DRYRUN}" != true ]]; then
            if [[ -x /usr/local/bin/lemper-jail-user && -d "${JAIL_ROOT}" ]]; then
                success "Jailkit installed and jail initialized at ${JAIL_ROOT}."
                info "Jail a user with: sudo lemper-jail-user <username>"
            else
                info "Something went wrong with Jailkit installation."
            fi
        else
            info "Jailkit installed in dry run mode."
        fi
    else
        info "Jailkit installation skipped."
    fi
}

echo "[Jailkit Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v jk_init) && "${FORCE_INSTALL}" != true ]]; then
    info "Jailkit already exists, installation skipped."
else
    init_jailkit_install "$@"
fi
