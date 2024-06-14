#!/usr/bin/env bash
set -eE -o pipefail

echo "INFO: Replacing fopenmp with qopenmp for ICPC in $(grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' "${1-${PWD:-.}}" || true)" >&2
grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' . | xargs -I _ sed -Ei 's/[-]fopenmp/-qopenmp/g' "_" || true
_fix_cmake_intel_openmp="$(grep  --include='*.txt' --include='*.cmake' -l -R -E '[-]fopenmp' "${1-${PWD:-.}}" || true)"
if [ -n "${_fix_cmake_intel_openmp:-}" ]; then
    echo "INFO: fopenmp still present in ${_fix_cmake_intel_openmp}" >&2
    exit 1
fi
