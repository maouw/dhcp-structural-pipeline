#!/bin/bash

# local directories
export parameters_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" 
export code_dir=$parameters_dir/..

# setup path from installation
[ ! -f $parameters_dir/path.sh ] || . $parameters_dir/path.sh

source "${DRAWEMDIR}/parameters/MCRIB/configuration.sh" || { echo "ERROR: Could not load MCRIB configuration from $_"; exit 1; }

# cortical structures of labels file
export cortical_structures="${CORTICAL?ERROR: CORTICAL not set}"

# lookup table used with the wb_command to load labels
export LUT="${DRAWEMDIR}/parameters/MCRIB/LUT.txt"

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
# v2 is for git master MIRTK with tuned pial generation

if [ -n "${DHCP_SURFACE_RECON_CONFIG_FILE:-}" ]; then
    DHCP_SURFACE_RECON_CONFIG_FILE="$parameters_dir/recon-neonatal-cortex"
    [ "${DHCP_SURFACE_RECON_CONFIG_VERSION:=2}" != "1" ] && DHCP_SURFACE_RECON_CONFIG_FILE="${DHCP_SURFACE_RECON_CONFIG_FILE}${DHCP_SURFACE_RECON_CONFIG_VERSION}"
    export DHCP_SURFACE_RECON_CONFIG_FILE="${DHCP_SURFACE_RECON_CONFIG_FILE}.cfg"
fi

if [ -f "${DHCP_SURFACE_RECON_CONFIG_FILE}" ]; then
    export surface_recon_config="${DHCP_SURFACE_RECON_CONFIG_FILE}"
else
    echo "ERROR: Surface reconstruction configuration file not found: ${DHCP_SURFACE_RECON_CONFIG_FILE}"
    exit 1
fi


# log function
run()
{
  echo "$@"
  /usr/bin/time -v "$@" 2>&1
  if [ ! $? -eq 0 ]; then
    echo "$@ : failed"
    exit 1
  fi
}

# make run function global
typeset -fx run

threads="${DHCP_NUM_THREADS:-${threads:-1}}"
[ "${threads}" -lt 1 ] && threads=$(nproc)
export OMP_NUM_THREADS="${threads}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${threads}"
export VTK_SMP_BACKEND_IN_USE="${VTK_SMP_BACKEND_IN_USE:-TBB}"
echo "Using threads: $threads; OMP_NUM_THREADS: $OMP_NUM_THREADS; ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS: $ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS; VTK_SMP_BACKEND_IN_USE: $VTK_SMP_BACKEND_IN_USE on machine with nproc=$(nproc)" >&2
