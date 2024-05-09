#!/bin/sh
# Set up build target directory and add to cmake prefixes
_oldflags="$-"; set +x

. "${ONEAPI_ROOT:-/opt/intel/oneapi}/setvars.sh" >/dev/null
export INTEL_OPTIMIZER_IPO="${INTEL_OPTIMIZER_IPO-"-ipo"}"
export INTEL_OPTIMIZER_FP_MODEL="${INTEL_OPTIMIZER_FP_MODEL-"-fp-model=precise"}"
export INTEL_OPTIMIZER_FLAGS="${INTEL_OPTIMIZER_FLAGS-"-static-intel -O3 -axCORE-AVX2,SKYLAKE-AVX512 -qopt-zmm-usage=high ${INTEL_OPTIMIZER_FP_MODEL:+ ${INTEL_OPTIMIZER_FP_MODEL:-}}${INTEL_OPTIMIZER_IPO:+ ${INTEL_OPTIMIZER_IPO:-}}"}"

export INTEL_MKL_TBB_DYNAMIC_FLAGS="-Wl,--push-state,--as-needed -L${MKLROOT}/lib/intel64 -lmkl_intel_lp64 -lmkl_tbb_thread -lmkl_core -lpthread -lm -ldl --pop-state"
export INTEL_MKL_TBB_STATIC_FLAGS="-Wl,--push-state,--as-needed -Wl,--start-group ${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_tbb_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -Wl,--end-group -static-intel -L${TBBROOT}/lib/intel64/gcc4.8 -ltbb -lstdc++ -lpthread -lm -ldl --pop-state"
export INTEL_MKL_OPENMP_DYNAMIC_FLAGS="-Wl,--push-state,--as-needed -L${MKLROOT}/lib/intel64 -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core -liomp5 -lpthread -lm -ldl --pop-state"
export INTEL_MKL_OPENMP_STATIC_FLAGS="-Wl,--push-state,--as-needed -Wl,--start-group -L${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -Wl,--end-group -static-intel -lpthread -lm -ldl -lpthread --pop-state"
export __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS-""}"
export __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS-"-w1 -diag-disable=10441 -diag-disable=15009 -diag-disable=10006 -diag-disable=10370 -diag-disable=10148 -diag-disable=10145 -wd10145 -no-cilk"}"

export CPATH="${DHCP_PREFIX}/include:${CPATH}"
export LIBRARY_PATH="${DHCP_PREFIX}/lib:${LIBRARY_PATH}"
export PKG_CONFIG_PATH="${DHCP_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH}"
ldconfig

export CMAKE_PREFIX_PATH="${DHCP_PREFIX}:${CMAKE_PREFIX_PATH:-}"
export CMAKE_INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX:-${DHCP_PREFIX}}"
export CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"

if [ "${USE_INTEL_COMPILER:-1}" = 1 ]; then
	command -v icc 2>/dev/null && export CC="$(command -v icc 2>/dev/null)"
	command -v icpc 2>/dev/null && export CXX="$(command -v icpc 2>/dev/null)"
fi

set_compiler_flags() {
	_oldflags="$-"; set +x

	export __INTEL_PRE_CFLAGS="-Wl,--as-needed ${__INTEL_PRE_CFLAGS:+${__INTEL_PRE_CFLAGS:-} }${1:-}"
	# Set optimizer flags
	export __INTEL_POST_CFLAGS="-Wl,--as-needed ${__INTEL_POST_CFLAGS:+${__INTEL_POST_CFLAGS:-} }${2:-} ${INTEL_OPTIMIZER_FLAGS:-}"

	# Set ncpus
	NCPU="${NCPU:-0}"
	total_nproc="$(nproc || grep -c '^processor[[:space:]]*:' /proc/cpuinfo || true)"
	total_nproc="${total_nproc:-0}"
	[ "$total_nproc" -le 0 ] && total_nproc=1

	[ "${NCPU}" -gt "${total_nproc}" ] && NCPU=0
	[ "${NCPU}" -le 0 ] && NCPU="$((total_nproc - 1))"
	[ "${NCPU}" -le 0 ] && NCPU=1
	export CMAKE_BUILD_PARALLEL_LEVEL="${NCPU}"
	export MAKEFLAGS="-j${NCPU}"

	echo "INFO: Using ${NCPU} cpus" >&2
	echo "INFO: Using __INTEL_PRE_CFLAGS=\"${__INTEL_PRE_CFLAGS:-}\"" >&2
	echo "INFO: Using __INTEL_POST_CFLAGS=\"${__INTEL_POST_CFLAGS:-}\"" >&2
	case "${_oldflags:-}" in *x*) set -x ;; esac
}

case "${_oldflags:-}" in *x*) set -x ;; esac
