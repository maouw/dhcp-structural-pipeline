#!/bin/bash
function __dhcp_debug_setx_output() {
    if [[ -n "${1:-}" ]]; then
        exec {BASH_XTRACEFD}>>"$1"
        PS4=' \D{%Y-%m-%d}T\T [$BASH_SOURCE:$LINENO] '
        set -x
    else
        set +x
        unset -v BASH_XTRACEFD
    fi
}

function __dhcp_debug_log_stdout() {
  exec &> >(ts '%Y-%m-%dT%H:%M:%S' | tee -a "${__log_stdout_path:-out.log}")
}

function __dhcp_debug_log_stderr() {
  exec &> >(ts '%Y-%m-%dT%H:%M:%S' | tee -a "${__log_stderr_path:-out.err}")
}


# appends a command to a trap
#
# - 1st arg:  code to add
# - remaining args:  names of traps to modify
#
# set the trace attribute for the above function.  this is
# required to modify DEBUG or RETURN traps because functions don't
# inherit them unless the trace attribute is set

function __dhcp_debug_trap__add () {
    local handler=$(trap -p "$2")
    handler=${handler/trap -- \'/}    # /- Strip `trap '...' SIGNAL` -> ...
    handler=${handler%\'*}            # \-
    handler=${handler//\'\\\'\'/\'}   # <- Unquote quoted quotes ('\'')
    trap "${handler} $1;" "$2"
}

declare -f -t __dhcp_debug_trap__add


#__setx_output

#debug_prompt () { echo "[$BASH_SOURCE:$LINENO] $BASH_COMMAND?" _ ; BASH_COMMAND='echo b'; }
#trap 'echo "<$_>"' DEBUG
#trap-add 'echo "Bye bye"' EXIT
#trap_add 'echo "in trap DEBUG"' DEBUG
# dump set -x data to a file
# turns on with a filename as $1
# turns off with no params
__setx_output "${OUTNAME}"
exec &> >(ts '%Y-%m-%dT%H:%M:%S' | tee -a log.out)

echo 'Hello from b'

echo 'Hello again from b'


