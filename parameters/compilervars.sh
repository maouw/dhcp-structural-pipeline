#!/bin/sh
# shellcheck disable=SC1091

# Unset BASH_ENV if it points to this script
[ -n "${BASH_VERSION:-}" ] && [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_ENV:-}" ] && [ "$(readlink -f "${BASH_ENV}")" = "$(readlink -f "${BASH_SOURCE}")" ] && export BASH_ENV=""

. "${ONEAPI_ROOT}/compiler/classic/env/vars.sh" >/dev/null || echo "WARNING: Could not load Intel Classic compiler." >&2
SETVARS_ARGS="--include-intel-llvm" . "${ONEAPI_ROOT}/setvars.sh" >/dev/null || echo "WARNING: Could not load Intel oneAPI vars." >&2

ldconfig

if ("${CC:-cc}" --version 2>/dev/null || true; "${CXX:-c++}" --version 2>/dev/null || true) | grep -q "ICC"; then
    # 10441: The Intel(R) C++ Compiler Classic (ICC) is deprecated and will be removed from product release in the second half of 2023. The Intel(R) oneAPI DPC++/C++ Compiler (ICX) is the recommended compiler moving forward. Please transition to use this compiler. Use 'xxxx' to disable this message.
    # 11074: Inlining inhibited by limit xxxx
    # 11075: To get full report use -Qopt-report:4 -Qopt-report-phase ipo
    # 11076: To get full report use -qopt-report=4 -qopt-report-phase ipo
    # 10429: Unsupported command line options encountered
    __INTEL_POST_CFLAGS="-diag-once=10441,11074,11075,11076,10429 -no-cilk${__INTEL_POST_CFLAGS:+ ${__INTEL_POST_CFLAGS:-}}"
elif ("${CC:-cc}" --version 2>/dev/null || true; "${CXX:-c++}" --version 2>/dev/null || true) | grep -q "Intel.*DPC"; then
    __INTEL_POST_CFLAGS="-Wno-unused-command-line-argument${__INTEL_POST_CFLAGS:+ ${__INTEL_POST_CFLAGS:-}}"
fi

[ -n "${__INTEL_POST_CFLAGS}" ] && export __INTEL_POST_CFLAGS
[ -n "${__INTEL_PRE_CFLAGS}" ] && export __INTEL_PRE_CFLAGS

# Set the number of CPUs to use for building:
export NCPU="${NCPU:-$(nproc)}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-${NCPU}}"

# Set up cmake to build with verbose output and time the build
cmake() {
    [ "${CLEAR_XTRACE:-1}" = 1 ] && __old_shell_opts="$-"; set +x
    which cmake >/dev/null 2>&1 || { echo "ERROR: cmake not found." >&2; return 1; }
    set -- "$(which cmake)" "$@"
    for __arg in "$@"; do
        case "${__arg}" in
            --build | --build-and-*)
                echo "Building with CMAKE_BUILD_PARALLEL_LEVEL=\"${CMAKE_BUILD_PARALLEL_LEVEL}\" (NCPU=${NCPU}/$(nproc))" >&2
                set -- /usr/bin/time -v "$@"
                break
                ;;
            *) ;;
        esac
    done
    "$@"
    case "${__old_shell_opts:-}" in *x*) set -x;; esac
    unset __old_shell_opts
}

# Set xtrace if in interactive mode
[ "${XTRACE:-1}" != 0 ] && case "$-" in *i*) set -x ;; esac
