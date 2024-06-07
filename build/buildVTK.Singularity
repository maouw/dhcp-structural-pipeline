Bootstrap: docker-archive
From: dhcp_builder.tar

%arguments
    ARG_INTEL_OPTIMIZER_FLAGS=-O3 -xSKYLAKE -axSKYLAKE-AVX512 -qopt-zmm-usage=high -fp-model=precise

%post -c /bin/bash
    PS4='+${LINENO:-} '
    set -eEx -o pipefail

    mkdir -p /opt/build/vtk && cd "$_"
    (git clone --branch release --single-branch --depth 1 https://github.com/Kitware/VTK src && cd "$_" && git submodule update --init --recursive)
    mkdir -p build && cd build

    export INTEL_OPTIMIZER_FLAGS="{{ARG_INTEL_OPTIMIZER_FLAGS}}"
    source "/opt/build/compilervars.sh"

    set_compiler_flags "" "-w2 -wd869 -wd593 -wd1286 -wd186 -wd612 -wd111 -wd654 -wd1125 -wd11074 -wd11076 -Wp,-DEIGEN_USE_MKL,-DEIGEN_USE_MKL_ALL ${INTEL_MKL_TBB_DYNAMIC_FLAGS}"
    export CUDAHOSTCXX="$(which g++-12)"
    export NVCC_CCBIN="${CUDAHOSTCXX}"
    export CUDAFLAGS="-std=c++17"
    export NVCC_APPEND_FLAGS="-Xcompiler=-DEIGEN_USE_MKL -Xcompiler=-DEIGEN_USE_MKL_ALL -Xcompiler=-std=c++17 -Xcompiler=-march=skylake -Xcompiler=-O3 -Xcompiler=-m64 -Xcompiler=-lstdc++ -Xcompiler=-mtune=skylake --forward-unknown-to-host-compiler --expt-relaxed-constexpr --extended-lambda  --generate-code arch=compute_75,code=sm_75 --generate-code arch=compute_86,code=sm_86 --generate-code arch=compute_75,code=sm_75 --generate-code arch=compute_89,code=sm_89"
    
    nice -n19 cmake \
        -D CMAKE_CXX_STANDARD=17 \
        -D BUILD_SHARED_LIBS:BOOL=ON \
        -D BUILD_TESTING:BOOL=OFF \
        -D VTK_ENABLE_REMOTE_MODULES:BOOL=OFF \
        -D VTK_ENABLE_WRAPPING=ON \
        -D VTK_GROUP_ENABLE_Qt:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Rendering:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_StandAlone:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Views:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Web:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmCore:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmDataModel:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmFilters:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonCore:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonDataModel:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonExecutionModel:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonMath:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonTransforms:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsMicroscopy:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_eigen:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_fides:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersCore:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersExtraction:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersFlowPaths:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeneral:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeometry:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersHybrid:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersModeling:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersOpenTURNS:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallel:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSMP:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSources:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingCore:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingStencil:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOADIOS2:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCesium3DTiles:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCGNSReader:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOChemistry:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCityGML:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCONVERGECFD:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOExport:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOFFMPEG:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGeometry:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGeometry:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOHDF:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOImage:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOImage:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOImport:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOIOSS:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLAS:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLegacy:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLSDyna:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMotionFX:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMovie:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMySQL:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOODBC:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallel:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallelXML:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPDAL:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPostgreSQL:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOVideo:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOXML:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelCore:STRING=WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingExternal:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingFreeTypeFontConfig:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingOpenVR:STRING=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WrappingTools:STRING=DONT_WANT \
        -D VTK_MODULE_USE_EXTERNAL_VTK_eigen:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_expat:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_jpeg:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_libxml2:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_lz4:BOOL=OFF \
        -D VTK_MODULE_USE_EXTERNAL_VTK_png:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_tiff:BOOL=ON \
        -D VTK_MODULE_USE_EXTERNAL_VTK_zlib:BOOL=OFF \
        -D VTK_SMP_ENABLE_TBB:BOOL=ON \
        -D VTK_SMP_IMPLEMENTATION_TYPE=TBB \
        -D VTK_USE_CUDA:BOOL=ON \
        -D VTK_USE_X:BOOL=OFF \
        -D VTK_WRAP_PYTHON:BOOL=ON \
        -D VTKm_ENABLE_CUDA:BOOL=ON \
        -D VTKm_ENABLE_DEVELOPER_FLAGS:BOOL=OFF \
        -D VTKm_ENABLE_RENDERING:BOOL=OFF \
        -D VTKm_ENABLE_TESTING:BOOL=OFF \
        -D VTKm_ENABLE_TBB:BOOL=ON \
        ../src || { tail -v -n 50 CMakeFiles/*.log 2>/dev/null || true; exit 1; }
    cmake --build . -- -j ${NCPU} -l ${NCPU}
