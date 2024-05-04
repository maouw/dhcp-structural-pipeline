#!/bin/sh
# Set up build target directory and add to cmake prefixes
_oldflags="$-"; set +x
ONEAPI_ROOT="${ONEAPI_ROOT:-/opt/intel/oneapi}"
INTEL_OPTIMIZER_FLAGS="${INTEL_OPTIMIZER_FLAGS:--O3 -fp-model=precise -mavx -axCORE-AVX2,CORE-AVX512}"

export CPATH="/opt/dhcp/include:${CPATH}"
export LIBRARY_PATH="/opt/dhcp/lib:${LIBRARY_PATH}"
export PKG_CONFIG_PATH="/opt/dhcp/share/pkgconfig:${PKG_CONFIG_PATH}"

# Static flags for build:
ldconfig

# Disable ICC deprecation warning and "targeted for automatic cpu dispatch" warning:
export __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS:+${__INTEL_PRE_CFLAGS:-} }-diag-disable=10441 -diag-disable=15009 -diag-disable=10006 -diag-disable=10370 -diag-disable=10148"

# Set optimizer flags
export __INTEL_POST_CFLAGS="${INTEL_OPTIMIZER_FLAGS:-}${__INTEL_POST_CFLAGS:+ ${__INTEL_POST_CFLAGS:-}}"

total_nproc="$(nproc || grep -c '^processor[[:space:]]*:' /proc/cpuinfo || true)"
total_nproc="${total_nproc:-0}"
[ "$total_nproc" -le 0 ] && total_nproc=1

# Set ncpus
NCPU="${NCPU:-0}"
[ "${NCPU}" -gt "${total_nproc}" ] && NCPU=0
[ "${NCPU}" -le 0 ] && NCPU="$((total_nproc - 1 ))"
[ "${NCPU}" -le 0 ] && NCPU=1
export CMAKE_BUILD_PARALLEL_LEVEL="${NCPU}"

echo "INFO: Using ${NCPU} cpus" >&2
echo "INFO: Using INTEL_OPTIMIZER_FLAGS=\"${INTEL_OPTIMIZER_FLAGS:-}\"" >&2
echo "INFO: Using __INTEL_PRE_CFLAGS=\"${__INTEL_PRE_CFLAGS:-}\"" >&2
echo "INFO: Using __INTEL_POST_CFLAGS=\"${__INTEL_POST_CFLAGS:-}\"" >&2

case "${_oldflags:-}" in *x*) set -x ;; esac
