#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Virtual Host (Site) Wrapper                                |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="site"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

if [ -z "${CLI_PLUGINS_DIR}" ]; then
    CLI_PLUGINS_DIR="/etc/lemper/cli-plugins"
fi

function site_subcmd_help() {
    cmd_help
}

function site_subcmd_version() {
    cmd_version
}

##
# LEMPer CLI 'site' subcommand wrapper.
#
# Usage:
#   lemper-cli site <command> [options] [<args>...]
##
function init_lemper_site() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        CMD="${1}"
        shift # Pass the remaining arguments to the next subcommand.

        case ${CMD} in
            help | -h | --help)
                site_subcmd_help
                exit 0
            ;;
            version | -v | --version)
                site_subcmd_version
                exit 0
            ;;
            *)
                if declare -f "site_subcmd_${CMD}" &>/dev/null 2>&1; then
                    # Run subcommand function if exists.
                    "site_subcmd_${CMD}" "$@"
                    exit 0
                elif [[ -x "${CLI_PLUGINS_DIR}/lemper-site-${CMD}" ]]; then
                    # Source the plugin executable file.
                    # shellcheck disable=SC1090
                    . "${CLI_PLUGINS_DIR}/lemper-site-${CMD}" "$@"
                    exit 0
                else
                    echo "${CMD_PARENT} ${CMD_NAME}: '${CMD}' is not ${CMD_NAME} subcommand"
                    echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information"
                    exit 1
                fi
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required arguments"
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information"
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_site "$@"
