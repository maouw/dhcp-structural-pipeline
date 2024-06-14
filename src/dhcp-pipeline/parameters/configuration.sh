#!/bin/bash
export PS4='+ $(date -Is) <${BASH_SOURCE[0]:-???}:${LINENO:-???}> '
set -x

# local directories
export parameters_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export code_dir=$parameters_dir/..

# setup path from installation
[ ! -f "$parameters_dir/path.sh" ] || . "$parameters_dir/path.sh"

# cortical structures of labels file
export cortical_structures="$(cat $DRAWEMDIR/parameters/cortical.csv)"

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

# log function

run() {
	local _run_saved_opts="$-"
	set +x
	_run_started="$(date +'%FT%T%z')"
	printf -v _run_log_ctx '%s [%s] <%s:%s> run "%q"' "${_run_started}" "$!" "${BASH_SOURCE[0]:-???}" "${LINENO:-???}" "$*"

	if command -v /usr/bin/time 1>/dev/null 2>&1; then
		_run_cmd=(/usr/bin/time -f "${_run_log_ctx}: elapsed=%E user=%U system=%S cpu=%P maxrss=%M I=%If O=%Ofsout c=%c w=%w W=%W")
	else
		export TIMEFORMAT="${_run_log_ctx}: elapsed=%RR user=%UU system=%SS cpu=%P%%"
		_run_cmd=(time)
	fi

	printf '%s\n' "${_run_log_ctx}" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION:-debug.log}"
	/usr/bin/time -f "${_run_log_ctx}: elapsed=%E user=%U system=%S cpu=%P maxrss=%M I=%I O=%O c=%c w=%w W=%W" "$@" 2>&1 | ts "%FT%T%z" | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION:-debug.log}" || {
		printf 'ERROR: Failed "%s"' "${_run_log_ctx}" | ts | tee --output-error=warn -a "${DEBUG_CENTRAL_LOG_LOCATION:-debug.log}"; exit 1; }

	case "${_run_saved_opts:-}" in
	*x*) set -x ;;
	*) ;;
	esac
	return 0
}

# make run function global
typeset -fx run
