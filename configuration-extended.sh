#!/bin/bash

# local directories
export parameters_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export code_dir=$parameters_dir/..

# setup path from installation
[ ! -f $parameters_dir/path.sh ] || . $parameters_dir/path.sh

# cortical structures of labels file
export cortical_structures=`cat $DRAWEMDIR/parameters/cortical.csv`

# lookup table used with the wb_command to load labels
export LUT=$DRAWEMDIR/parameters/segAllLut.txt

# tissue labels of tissue-labels file
export CSF_label=1
export CGM_label=2
export WM_label=3
export BG_label=4

# MNI T1, mask and warps
export MNI_T1=$code_dir/atlases/MNI/MNI152_T1_1mm.nii.gz
export MNI_mask=$code_dir/atlases/MNI/MNI152_T1_1mm_facemask.nii.gz
export MNI_dofs=$code_dir/atlases/non-rigid-v2/dofs-MNI

# Average space atlas name, T2 and warps
export template_name="non-rigid-v2"
export template_T2=$code_dir/atlases/non-rigid-v2/T2
export template_dofs=$code_dir/atlases/non-rigid-v2/dofs
export template_min_age=28
export template_max_age=44

# registration parameters
export registration_config=$parameters_dir/ireg-structural.cfg
export registration_config_template=$parameters_dir/ireg.cfg

# surface reconstuction parameters
export surface_recon_config=$parameters_dir/recon-neonatal-cortex.cfg

# ## DEBUGGING ADDITIONS
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
    saved_opts="$-"
    set +x
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
    timefile="$(mktemp)"
    /bin/time -f 
    /usr/bin/time -o "${timefile}" -f '(%U/%S/%E CPU=%P MaxRSS=%MK IN=%I OUT=%O ?%x) %C' "$@" || {
        builtin printf -v _run_log_ctx '%(%Y-%m-%d %H:%M:%S)T %s: ' "${_run_log_bash_source_ctx:-}" "$( cat "${timefile}" || true)"
        printf "%sFAILED! \nContext:\n" "${_run_log_ctx}\n" "$(pr -tn "${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-}}" | tail -n+$((${BASH_LINENO[0]:-${BASH_LINENO[0]:-3}} - 3)) | head -n7 || true)" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION}"
        rm -f "${timefile}"
        exit 1
    }
    rm "${timefile}"
    _run_prevdatetime="${_run_curdatetime}"
    case "${saved_opts:-}" in 
        *x*) set -x ;;
        *) ;;
    esac
}

# make run function global
typeset -fx run


if [[ "${DEBUG_XTRACE:-}" == 1 ]]; then
    # Initialize log if necessary:
    DEBUG_XTRACE_TO_FILE="${DEBUG_XTRACE_TO_FILE:-${DEBUG_XTRACE_LOG_LOCATION:+1}}"
    if [[ "${DEBUG_XTRACE_TO_FILE:-}" == 1 ]]; then
        if [[ -z "${DEBUG_XTRACE_LOG_LOCATION:-}" ]]; then
            [[ -n "${logdir:-}" ]] && builtin printf -v DEBUG_XTRACE_LOG_LOCATION '%s/trace-%(%Y%m%dT%H%M%S)T.log' "${logdir}" "${STARTED_AT}"
        fi
        [[ -n "${DEBUG_XTRACE_LOG_LOCATION:-}" ]] && mkdir -p "$(dirname "${DEBUG_XTRACE_LOG_LOCATION}")"
    
        if [[ "${DEBUG_XTRACE_LOG_LOCATION:-/dev/null}" != "/dev/null"  ]]; then
            export DEBUG_XTRACE_LOG_LOCATION
            mkdir -p "$(dirname "${DEBUG_XTRACE_LOG_LOCATION}")" || true
            exec {BASH_XTRACEFD}>>"${DEBUG_XTRACE_LOG_LOCATION}" || true
        fi
    fi
    if [[ -n "${DEBUG_XTRACE_PS4:-}" ]]; then
        PS4="${DEBUG_XTRACE_PS4:-}"
    else
        PS4='+ $(builtin printf "%(%H:%M)T") ${BASH_SOURCE[0]##*/}:${BASH_LINENO[0]}: '
    fi
    export PS4
fi
[[ "${DEBUG_XTRACE:-}" == 1 ]] && export DEBUG_XTRACE && set -x
[[ -n "${DEBUG_ADD_SHELL_OPTS:-}" ]] && set -"${DEBUG_ADD_SHELL_OPTS}"
[[ -n "${DEBUG_REMOVE_SHELL_OPTS:-}" ]] && set +"${DEBUG_REMOVE_SHELL_OPTS}"
