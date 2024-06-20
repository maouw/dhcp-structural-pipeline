#!/usr/bin/env bash
export PS4='+ [$BASH_SOURCE:$LINENO] '
if [[ "${DHCP_DEBUG:-1}" != 0 ]]; then
        function __dhcp_debug_setx_output() {
            if [[ -n "${__DHCP_DEBUG_PATH_GLOB:-}" ]]; then
                declare -p BASH_SOURCE >&2
                echo "Checking $(readlink -f "${BASH_SOURCE[1]}") against ${__DHCP_DEBUG_PATH_GLOB} ..." >&2
                # shellcheck disable=SC2053
                if (shopt -s extglob; [[ "$(readlink -f "${BASH_SOURCE[1]}")" != ${__DHCP_DEBUG_PATH_GLOB} ]]); then
                    return 0
                fi
            fi
            echo "File matches ${__DHCP_DEBUG_PATH_GLOB:-}" >&2

            if [[ -z "${BASH_XTRACEFD:-}" ]]; then
                __DHCP_DEBUG_LOG_PATH="${1:-${__DHCP_DEBUG_LOG_PATH:-${PWD}/log/debug.log}}"
                exec {BASH_XTRACEFD}>>"${__DHCP_DEBUG_LOG_PATH}"
                echo "BASH_XTRACEFD now points to \"${__DHCP_DEBUG_LOG_PATH}\"" >&2
            fi
        }
        declare -f -t __dhcp_debug_setx_output

    if [[ -z "${__DHCP_DEBUG_LOG_STARTED_AT:-}" ]]; then
        echo "Logging to ${1:-${__DHCP_DEBUG_LOG_PATH:-debug.log}}" >&2
        exec &> >(ts '%FT%T' | tee -a "${1:-${__DHCP_DEBUG_LOG_PATH:-debug.log}}")
        export __DHCP_DEBUG_LOG_STARTED_AT="${EPOCHSECONDS:-0}"
    fi
    trap 'trap - DEBUG; __dhcp_debug_setx_output' DEBUG
    set -x
fi
