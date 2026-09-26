#!/usr/bin/env bash

# Automated backup (Restic) Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 20.04
# Last Build        : 25/09/2026
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.7

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

BACKUP_KEY_FILE="/etc/lemper/backup.key"
BACKUP_SCRIPT="/etc/lemper/backup.sh"
BACKUP_CRON_FILE="/etc/cron.d/lemper-backup"
BACKUP_REPO=${BACKUP_REPO:-"/var/backups/lemper"}

function init_backup_removal() {
    # Remove the scheduled cron job first so no backup runs mid-removal.
    if [[ -f "${BACKUP_CRON_FILE}" ]]; then
        echo "Removing backup cron job..."
        run rm -f "${BACKUP_CRON_FILE}"
    else
        info "Backup cron job not found."
    fi

    # Optionally remove the backup runner script and key.
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_BACKUP_SCRIPT="y"
        else
            REMOVE_BACKUP_SCRIPT="n"
        fi
    else
        while [[ "${REMOVE_BACKUP_SCRIPT}" != "y" && "${REMOVE_BACKUP_SCRIPT}" != "n" ]]; do
            read -rp "Remove backup runner script and repository key (${BACKUP_SCRIPT}, ${BACKUP_KEY_FILE})? [y/n]: " -e REMOVE_BACKUP_SCRIPT
        done
    fi

    if [[ "${REMOVE_BACKUP_SCRIPT}" == y* || "${REMOVE_BACKUP_SCRIPT}" == Y* ]]; then
        [[ -f "${BACKUP_SCRIPT}" ]] && run rm -f "${BACKUP_SCRIPT}"
        [[ -f "${BACKUP_KEY_FILE}" ]] && run rm -f "${BACKUP_KEY_FILE}"
        echo "Backup runner script and repository key removed."
    else
        info "Backup runner script and repository key kept."
    fi

    # Optionally remove the Restic binary.
    if [[ -z $(command -v restic) ]]; then
        info "Restic binary not found."
    else
        if [[ "${AUTO_REMOVE}" == true ]]; then
            if [[ "${FORCE_REMOVE}" == true ]]; then
                REMOVE_RESTIC_BIN="y"
            else
                REMOVE_RESTIC_BIN="n"
            fi
        else
            while [[ "${REMOVE_RESTIC_BIN}" != "y" && "${REMOVE_RESTIC_BIN}" != "n" ]]; do
                read -rp "Remove Restic binary ($(command -v restic))? [y/n]: " -e REMOVE_RESTIC_BIN
            done
        fi

        if [[ "${REMOVE_RESTIC_BIN}" == y* || "${REMOVE_RESTIC_BIN}" == Y* ]]; then
            # Only remove the binary we installed; leave distro packages alone.
            if [[ "$(command -v restic)" == "/usr/local/bin/restic" ]]; then
                run rm -f /usr/local/bin/restic
                echo "Restic binary removed."
            else
                warning "Restic found at $(command -v restic), not installed by LEMPer. Leaving it in place."
            fi
        else
            info "Restic binary kept."
        fi
    fi

    # Repository data: keep by default, explicit opt-in to delete.
    warning "!! Backup repository data is kept at ${BACKUP_REPO} !!"
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_BACKUP_REPO="n"
    else
        while [[ "${REMOVE_BACKUP_REPO}" != "y" && "${REMOVE_BACKUP_REPO}" != "n" ]]; do
            read -rp "Permanently DELETE all backup repository data at ${BACKUP_REPO}? [y/n]: " -e REMOVE_BACKUP_REPO
        done
    fi

    if [[ "${REMOVE_BACKUP_REPO}" == y* || "${REMOVE_BACKUP_REPO}" == Y* ]]; then
        warning "!! This action is not reversible !!"
        if [[ -d "${BACKUP_REPO}" ]]; then
            run rm -fr "${BACKUP_REPO}"
            echo "Backup repository data deleted permanently."
        else
            info "Backup repository directory not found."
        fi
    else
        info "Backup repository data kept at ${BACKUP_REPO}."
        info "To restore later, reinstall Restic and use the repository password from your records."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ ! -f "${BACKUP_CRON_FILE}" ]]; then
            success "Automated backup (Restic) removed successfully."
        else
            info "Unable to remove automated backup cron job."
        fi
    else
        info "Automated backup removed in dry run mode."
    fi
}

echo "Uninstalling automated backup (Restic)..."

if [[ -f "${BACKUP_CRON_FILE}" || -f "${BACKUP_SCRIPT}" || -n $(command -v restic) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_BACKUP="y"
    else
        while [[ "${REMOVE_BACKUP}" != "y" && "${REMOVE_BACKUP}" != "n" ]]; do
            read -rp "Are you sure to remove automated backup (Restic)? [y/n]: " -e REMOVE_BACKUP
        done
    fi

    if [[ "${REMOVE_BACKUP}" == y* || "${REMOVE_BACKUP}" == Y* ]]; then
        init_backup_removal "$@"
    else
        echo "Found automated backup installation, but not removed."
    fi
else
    info "Oops, automated backup installation not found."
fi
