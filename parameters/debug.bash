#!/usr/bin/env bash

export PS4='+ [$BASH_SOURCE:$LINENO]'

if [[ "${DHCP_DEBUG:-1}" != 0 ]]; then
        function __dhcp_debug_setx_output() {
                # shellcheck disable=SC2053
                if [[ -n "${BASH_SOURCE[1]:-}" ]] && (shopt -s extglob; [[ "$(readlink -f "${BASH_SOURCE[1]:-}")" == ${__DHCP_DEBUG_PATH_GLOB:-*} ]]); then
                    echo "Enabling -x for ${BASH_SOURCE[1]:-}" >&2
                    set -x
                fi
        }
        declare -f -t __dhcp_debug_setx_output
        trap 'trap - DEBUG; __dhcp_debug_setx_output' DEBUG
fi

