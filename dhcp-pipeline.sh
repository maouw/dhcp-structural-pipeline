#!/bin/bash
set -eET -o pipefail

# if FSLDIR is not defined, assume we need to read the FSL startup
if [ -z "${FSLDIR+x}" ]; then
    if [ -f /etc/fsl/fsl.sh ]; then
        . /etc/fsl/fsl.sh
    else
        echo FSLDIR is not set and there is no system-wide FSL startup
        exit 1
    fi
fi

usage() {
    base=$(basename "$0")
    echo "usage: ${base} <subject_ID> <session_ID> <scan_age> -T2 <subject_T2.nii.gz> [-T1 <subject_T1.nii.gz>] [options]
This script runs the dHCP structural pipeline.

Arguments:
  subject_ID                    subject ID
  session_ID                    session ID
  scan_age                      Number: Subject age in weeks. This is used to select the appropriate template for the initial registration.
                                If the age is <28w or >44w, it will be set to 28w or 44w respectively.
  -T2 <subject_T2.nii.gz>       Nifti Image: The T2 image of the subject
  -T1 <subject_T1.nii.gz>       Nifti Image: The T1 image of the subject (Optional)

Options:
  -d / -data-dir  <directory>   The directory used to run the script and output the files.
  -additional                   If specified, the pipeline will produce some additional files not included in release v1.0 (such as segmentation prob.maps, warps to MNI space, ..) (default: False)
  -t / -threads  <number>       Number of threads (CPU cores) used (default: 1)
  -no-reorient                  The images will not be reoriented before processing (using the FSL fslreorient2std command) (default: False)
  -no-cleanup                   The intermediate files produced (workdir directory) will not be deleted (default: False)
  -use-recon-neonatal-cortex-v1) Use recon-neonatal-cortex.cfg from earlier version of the dhcp pipeline (default: False)
  -set-surf) Specify surfaces for the surface pipeline (default: 'white pial midthickness inflated very_inflated sphere')
  -h / -help / --help           Print usage.
"
    exit 1
}


# log function for completion
runpipeline() {
    pipeline=$1
    shift
    echo "Running ${pipeline} pipeline: $*"
    /usr/bin/time "$@" || {  echo "Pipeline $pipeline failed with code \"$?\""; exit 1; }
    echo "-----------------------"
}

################ Arguments ################

[ $# -ge 3 ] || { usage; }
command=$@
subjectID=$1
sessionID=$2
age=$3
shift; shift; shift;

# alias for the specific session
subj=${subjectID}-${sessionID}
T1="-"
T2="-"
datadir=$(pwd)
threads="${DHCP_NUM_THREADS:-0}"
minimal=1
noreorient=0
cleanup=1
while [ $# -gt 0 ]; do
    case "$1" in
        -T2) shift; T2="$1" ;;
        -T1) shift; T1="$1" ;;
        -d | -data-dir) shift; datadir="$1" ;;
        -t | -threads) shift; threads="$1" ;;
        -additional) minimal=0 ;;
        -no-reorient) noreorient=1 ;;
        -no-cleanup) cleanup=0 ;;
        -use-recon-neonatal-cortex-v1) export surface_recon_config_filename="recon-neonatal-cortex.cfg" ;;
        -set-surf) shift; export DHCP_USE_SURF="$1" ;;
        -h | -help | --help) usage ;;
        -*) echo "$0: Unrecognized option $1" >&2; usage ;;
        *) break ;;
    esac
    shift
done

# consider the case where the user is running us inside docker with an
# argument like:
#
#	-T2 data/T1w.nii.gz
#
# the user's data directory will be mapped to /data, and that's out WORKDIR,
# so we need to remove the leading data/ component for the path to be valid
#
# we don't want to make this change unless we have to, so only drop the first
# pathname component if the file named by T2 does not exist and	T2 is a
# relative path

if [[ "${T2}" != /* && ! -f "${T2}" ]]; then
    T1=${T1#*/}
    T2=${T2#*/}
fi

################ Checks ################

{ [[ "${T2}" != "-" ]] && [[ "${T2}" != "" ]]; } || { echo "T2 image not provided!" >&2; exit 1; }

# check whether the different tools are set and load parameters
codedir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
echo "Using code directory ${codedir}" >&2
[ -d "${codedir}" ] || { echo "The code directory does not exist!" >&2; exit 1; }

source ${codedir}/parameters/configuration.sh

scriptdir="${codedir}/scripts"

roundedAge=$(printf "%.*f\n" 0 "${age}") #round
[ "${roundedAge}" -lt "${template_max_age}" ] || { roundedAge=${template_max_age}; }
[ "${roundedAge}" -gt "${template_min_age}" ] || { roundedAge=${template_min_age}; }


################ Run ################
version="$(cat "${codedir}"/version)"
echo "dHCP-pipeline ${version}
Subject: ${subjectID}
Session: ${sessionID}
Age: ${age}
T1: ${T1}
T2: ${T2}
Directory: ${datadir}
Threads: ${threads}
nproc: $(nproc)
surface_recon_config: ${surface_recon_config}
VTK_SMP_BACKEND_IN_USE: ${VTK_SMP_BACKEND_IN_USE}
ITK_GLOBAL_DEFAULT_THREADER: ${ITK_GLOBAL_DEFAULT_THREADER}
Minimal: ${minimal}" | column -t
[ "${threads}" -eq 1 ] || { echo "Warning: Number of threads>1: This may result in minor reproducibility differences"; }
echo "

${BASH_SOURCE[0]} ${command}
----------------------------"

last_file=${datadir}/derivatives/sub-${subjectID}/ses-${sessionID}/anat/Native/sub-${subjectID}_ses-${sessionID}_wb.spec
if [ -f "${last_file}" ]; then echo "dHCP pipeline already completed!"; exit; fi

# infodir=${datadir}/info
export DHCP_LOGDIR="${DHCP_LOGDIR:-${datadir}/log}"
logdir="${DHCP_LOGDIR}"
export DHCP_WORKDIR="${DHCP_WORKDIR:-${datadir}/workdir}"
workdir="${DHCP_WORKDIR}"
# mkdir -p ${infodir}
mkdir -p "${workdir}" "${logdir}"

echo "Logging to ${DHCP_LOGDIR}/debug.log" >&2
exec &> >(ts '%FT%T' | tee -a "${DHCP_LOGDIR}/debug.log")
# copy files in the T1/T2 directory
for modality in T1 T2; do
    mf=${!modality};
    if [ "${mf}" == "-" -o "${mf}" == "" ]; then continue; fi
    if [ ! -f "${mf}" ]; then echo "The \"${modality}\" image provided as argument does not exist!" >&2; exit 1; fi

    mkdir -p "${workdir}/${modality}"
    newf=${workdir}/${modality}/${subj}.nii.gz
    if [ "${noreorient}" -eq 1 ]; then
        cp "${mf}" "${newf}"
    else
        fslreorient2std "${mf}" ${newf}
    fi
    eval "${modality}=${newf}"
done

# segmentation

echo "Using surface reconstruction configuration file: ${DHCP_SURFACE_RECON_CONFIG_FILE}" >&2
runpipeline segmentation "${scriptdir}/segmentation/pipeline.sh" "${T2}" "${subj}" "${roundedAge}" -d "${workdir}" -t "${threads}"

# generate some additional files
runpipeline additional "${scriptdir}/misc/pipeline.sh" "${subj}" "${roundedAge}" -d "${workdir}" -t "${threads}"

# surface extraction
runpipeline surface "${scriptdir}/surface/pipeline.sh" "${subj}" -d "${workdir}" -t "${threads}"

if [ "${DHCP_EXIT_AFTER_CREATE_MYELIN_MAP:-0}" -eq 1 ]; then
    echo "Exiting after creating myelin map"
    exit 0
fi

# create data directory for subject
runpipeline structure-data "${scriptdir}/misc/structure-data.sh" "${subjectID}" "${sessionID}" "${subj}" "${roundedAge}" "${datadir}" "${workdir}" "${minimal}"

# clean-up
if [ "${cleanup}" -eq 1 ]; then
    runpipeline cleanup rm -r "${workdir}"
fi

echo "dHCP pipeline completed!"
