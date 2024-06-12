#!/bin/bash

function __dhcp_debug_setx_output() {
    if [ -n "${1:-}" ]; then
        eval 'exec {BASH_XTRACEFD}>>"$1"'
        PS4=' \D{%Y-%m-%d}T\T [$BASH_SOURCE:$LINENO] '
        set -x
    else
        set +x
        unset -v BASH_XTRACEFD
    fi
}

function __dhcp_debug_log_stdout() {
  exec &> >(ts '%Y-%m-%dT%H:%M:%S' | tee -a "$@")
}

function __dhcp_debug_log_stderr() {
  exec &> >(ts '%Y-%m-%dT%H:%M:%S' | tee -a "$@" >&2)
}

function __dhcp_debug_trap_add() {
    local __dhcp_debug_trap_add_handler=$(trap -p "$2")
    __dhcp_debug_trap_add_handler=${__dhcp_debug_trap_add_handler/trap -- \'/}    # /- Strip `trap '...' SIGNAL` -> ...
    __dhcp_debug_trap_add_handler=${__dhcp_debug_trap_add_handler%\'*}            # \-
    __dhcp_debug_trap_add_handler=${__dhcp_debug_trap_add_handler//\'\\\'\'/\'}   # <- Unquote quoted quotes ('\'')
    trap "${__dhcp_debug_trap_add_handler} $1;" "$2"
}
declare -f -t __dhcp_debug_trap__add


if [[ -n "${DHCP_DEBUG_LOG_DIR}" ]]; then
    mkdir -p "${DHCP_DEBUG_LOG_DIR}" || exit 1
    __dhcp_debug_log_stdout "${DHCP_DEBUG_LOG_DIR}/stdout.log"
    __dhcp_debug_log_stderr "${DHCP_DEBUG_LOG_DIR}/stderr.log"
    __dhcp_debug_setx_output "${DHCP_DEBUG_LOG_DIR}/setx.log"
fi
