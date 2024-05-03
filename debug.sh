#!/usr/bin/env bash
# Set time started at:
builtin printf -v STARTED_AT '%(%s)T'

# Set SECONDS to the start time
# In Bash:
#   Each time this parameter is referenced, the number  of  seconds
#   since  shell invocation is returned.  If a value is assigned to
#   SECONDS, the value returned upon subsequent references  is  the
#   number of seconds since the assignment plus the value assigned.
#   If SECONDS is unset, it loses its special properties,  even  if
#   it is subsequently reset.
SECONDS="${STARTED_AT}"

# log function
function run() {
    # Set current time and timestamp"
    _run_curtime="${SECONDS}"
    builtin printf -v _run_curdatetime '%(%Y-%m-%d %H:%M:%S)T' "${_run_curtime}"
    _run_prevdatetime="${_run_prevdatetime:-}"
    if [[ "${_run_curdatetime% *}" != "${_run_prevdatetime% *}" ]]; then
        _run_log_timestamp="${_run_curdatetime#* }"
    else
        _run_log_timestamp="${_run_curdatetime}"
    fi

    _run_bash_source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-}}"
    _run_log_bash_source_ctx=
    if [[ -n "${_run_bash_source:-}" ]]; then
        [[ "${_run_bash_source::1}" == "/" ]] && _run_log_bash_source_ctx="/"
        _run_bash_source="${_run_bash_source%/}"
        _run_bash_source_filename="${_run_bash_source##*/}"
        _run_bash_source_dir="${_run_bash_source%/*}"
        _run_bash_source_dirname="${_run_bash_source_dir##*/}"
        _run_bash_source_dirparents="${_run_bash_source_dir%/*}"
        _run_bash_source_dirparent_ctx="${_run_bash_source_dirparents//[^\/]/}"
        _run_bash_source_dirparent_ctx="${_run_bash_source_dirparent_ctx//\//*}"
        _run_log_bash_source_ctx="${_run_log_bash_source_ctx:-}${_run_bash_source_dirparent_ctx:+${_run_bash_source_dirparent_ctx}/}${_run_bash_source_dirname:+${_run_bash_source_dirname}/}${_run_bash_source_filename:-}:${BASH_LINENO[0]:-}${FUNCNAME[1]:+ in ${FUNCNAME[1]}() }"
    fi
    _run_log_ctx="${_run_log_timestamp:+${_run_log_timestamp}${_run_log_bash_source_ctx:+ }}${_run_log_bash_source_ctx:-}: "

    # Initialize log if necessary:
    if [[ -z "${DEBUG_CENTRAL_LOG_LOCATION:-}" ]]; then
        if [[ -n "${logdir:-}" ]]; then
            mkdir -p "${logdir}"
            builtin printf -v DEBUG_CENTRAL_LOG_LOCATION '%s/all-%(%Y%m%dT%H%M%S)T.log' "${logdir}" "${STARTED_AT}"
            export DEBUG_CENTRAL_LOG_LOCATION
            printf '%s: Started logging to "%s"\n' "${_run_curdatetime}" "${DEBUG_CENTRAL_LOG_LOCATION}" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION}"
        fi
    fi
    DEBUG_CENTRAL_LOG_LOCATION="${DEBUG_CENTRAL_LOG_LOCATION:-/dev/null}"

    printf "%sRUN \"%s\"\n" "${_run_log_ctx}" "$*" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION}"
    "$@" || {
        printf "%sFAILED RUN \"%s\"\nContext:\n" "${_run_log_ctx}" "$*" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION}"
        pr -tn "${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-}}" | tail -n+$((${BASH_LINENO[0]:-${BASH_LINENO[0]:-3}} - 3)) | head -n7 | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION}" || true


        exit 1
    }
    _run_prevdatetime="${_run_curdatetime}"
}

# make run function global
typeset -fx run

if [[ "${DEBUG_XTRACE:-}" == 1 ]]; then
    # Initialize log if necessary:
    if [[ -z "${DEBUG_XTRACE_LOG_LOCATION:-}" ]]; then
        if [[ -n "${logdir:-}" ]]; then
            mkdir -p "${logdir}"
            builtin printf -v DEBUG_XTRACE_LOG_LOCATION '%s/trace-%(%Y%m%dT%H%M%S)T.log' "${logdir}" "${STARTED_AT}"
            export DEBUG_XTRACE_LOG_LOCATION
        fi
    fi
    if [[ "${DEBUG_XTRACE_LOG_LOCATION:-/dev/null}" != "/dev/null"  ]]; then
        exec {BASH_XTRACEFD}>>"${DEBUG_XTRACE_LOG_LOCATION}"
    fi
    export PS4='+ $(builtin printf %(%Y-%m-%d %H:%M:%S)T) "${BASH_SOURCE[0]:-}":${LINENO}: '
fi

[[ "${DEBUG_XTRACE:-}" == 1 ]] && export DEBUG_XTRACE && set -x
[[ -n "${DEBUG_ADD_SHELL_OPTS:-}" ]] && set -"${DEBUG_ADD_SHELL_OPTS}"
[[ -n "${DEBUG_REMOVE_SHELL_OPTS:-}" ]] && set +"${DEBUG_REMOVE_SHELL_OPTS}"
