#!/bin/sh
# Set up build target directory and add to cmake prefixes
_oldflags="$-"; set +x

export SETVARS_ARGS="--include-intel-llvm"

. "${ONEAPI_ROOT:-/opt/intel/oneapi}/setvars.sh" >/dev/null
export INTEL_OPTIMIZER_FP_MODEL="${INTEL_OPTIMIZER_FP_MODEL-"-fp-model=precise"}"
export INTEL_OPTIMIZER_FLAGS="${INTEL_OPTIMIZER_FLAGS-"-O3 -xCORE-AVX2 -axSKYLAKE-AVX512 -qopt-zmm-usage=high ${INTEL_OPTIMIZER_FP_MODEL:+ ${INTEL_OPTIMIZER_FP_MODEL:-}}${INTEL_OPTIMIZER_IPO:+ ${INTEL_OPTIMIZER_IPO:-}}"}"

export INTEL_MKL_TBB_DYNAMIC_FLAGS="-Wl,--push-state,--as-needed -L${MKLROOT}/lib/intel64 -lmkl_intel_lp64 -lmkl_tbb_thread -lmkl_core -lpthread -lm -ldl --pop-state"
export INTEL_MKL_TBB_STATIC_FLAGS="-Wl,--push-state,--as-needed -Wl,--start-group ${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_tbb_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -Wl,--end-group -L${TBBROOT}/lib/intel64/gcc4.8 -ltbb -lstdc++ -lpthread -lm -ldl --pop-state"
export INTEL_MKL_OPENMP_DYNAMIC_FLAGS="-Wl,--push-state,--as-needed -L${MKLROOT}/lib/intel64 -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core -liomp5 -lpthread -lm -ldl --pop-state"
export INTEL_MKL_OPENMP_STATIC_FLAGS="-Wl,--push-state,--as-needed -Wl,--start-group -L${MKLROOT}/lib/intel64/libmkl_intel_lp64.a ${MKLROOT}/lib/intel64/libmkl_intel_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -Wl,--end-group -liomp5 -lpthread -lm -ldl -lpthread --pop-state"
export EIGEN_MKL_FLAGS="-Wp,-DEIGEN_USE_MKL"
export EIGEN_MKL_ALL_FLAGS="-Wp,-DEIGEN_USE_MKL,-DEIGEN_USE_MKL_ALL"
export EIGEN_CUDA_FLAGS="-Wp,-DEIGEN_USE_GPU"

export __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS-""}"
export __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS-"-diag-disable=10441 -diag-disable=15009 -diag-disable=10006 -diag-disable=10370 -diag-disable=10148 -diag-disable=10145 -wd10145 -no-cilk"}"

export CPATH="${DHCP_PREFIX}/include:${CPATH}"
export LIBRARY_PATH="${DHCP_PREFIX}/lib:${LIBRARY_PATH}"
export PKG_CONFIG_PATH="${DHCP_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH}"
ldconfig

export CMAKE_PREFIX_PATH="${DHCP_PREFIX}:${CMAKE_PREFIX_PATH:-}"
export CMAKE_INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX:-${DHCP_PREFIX}}"
export CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
export CUDAARCHS="${CUDAARCHS:-75;86}"

if [ -d "/usr/local/cuda/bin" ]; then
	export CUDA_TOOLKIT_ROOT=/usr/local/cuda-12
	export CUDACXX="${CUDA_TOOLKIT_ROOT}/bin/nvcc"
fi

if [ "${USE_INTEL_COMPILER:-1}" = 1 ]; then
	command -v icc 2>/dev/null && export CC="$(command -v icc 2>/dev/null)"
	command -v icpc 2>/dev/null && export CXX="$(command -v icpc 2>/dev/null)"
fi

fix_cmake_intel_openmp () {
    echo "INFO: Replacing fopenmp with qopenmp for ICPC in $(grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' . || true)" >&2
    grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' . | xargs -I _ sed -Ei 's/[-]fopenmp/-qopenmp/g' "_" || true
    _fix_cmake_intel_openmp="$(grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' . || true)"
    if [ -n "${_fix_cmake_intel_openmp:-}" ]; then
    	echo "INFO: fopenmp still present in ${_fix_cmake_intel_openmp}" >&2
    	exit 1
    fi
}

set_compiler_flags() {
	_oldflags="$-"; set +x

	export __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS:+${__INTEL_PRE_CFLAGS:-} }${1:-}"
	# Set optimizer flags
	export __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS:+${__INTEL_POST_CFLAGS:-} }${2:-} ${INTEL_OPTIMIZER_FLAGS:-}"


    export NCPU="${NCPU:-$(nproc)}"
    export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-${NCPU}}"
    
	echo "INFO: Using ${NCPU} cpus with CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL}" >&2
	echo "INFO: Using __INTEL_PRE_CFLAGS=\"${__INTEL_PRE_CFLAGS:-}\"" >&2
	echo "INFO: Using __INTEL_POST_CFLAGS=\"${__INTEL_POST_CFLAGS:-}\"" >&2
	case "${_oldflags:-}" in *x*) set -x ;; esac
}

case "${_oldflags:-}" in *x*) set -x ;; esac
