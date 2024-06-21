# syntax=docker/dockerfile:1.7-labs
## Build Docker image for execution of dhcp pipelines within a Docker
## container with all modules and applications available in the image

# == BASE IMAGE ==

# Specify BUILD_WITH_CUDA=12.4.1 etc. if you need CUDA
ARG BUILD_WITH_CUDA
ARG BASE_IMAGE="mambaorg/micromamba:jammy${BUILD_WITH_CUDA:+-cuda-${BUILD_WITH_CUDA}}"
FROM ${BASE_IMAGE} AS base
LABEL stage=base
LABEL BASE_IMAGE="${BASE_IMAGE}"
LABEL BUILD_WITH_CUDA="${BUILD_WITH_CUDA}"

USER root

# Global system-level config
ENV TZ=UTC \
    LANGUAGE=en_US:en \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# Force apt to leave downloaded binaries in /var/cache/apt (massively speeds up Docker builds)
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Acquire::Queue-Mode: Queuing mode; Queue-Mode can be one of host or access which determines how APT parallelizes outgoing connections. host means that one connection per target host will be opened, access means that one connection per URI type will be opened.
RUN echo 'Acquire::Queue-Mode "host";' > /etc/apt/apt.conf.d/99queue

# Set up basic environment
ENV DHCP_PREFIX="/opt/dhcp"
ENV DRAWEMDIR="${DHCP_PREFIX}/share/DrawEM"
ENV FSLDIR="${DHCP_PREFIX}/fsl"
ENV PATH="${DHCP_PREFIX}/bin:${FSLDIR}/bin:${DHCP_PREFIX}/bin:${PATH}"
ENV ONEAPI_ROOT="/opt/intel/oneapi"
ENV TIME="user=%U sys=%S wall=%E cpu=%P %% mmax=%MK mavg=%kK i=%I o=%O swap=%W # %C"
ENV TSFORMAT="%FT%H:%M:%S"
ENV PYTHONPATH="${DHCP_PREFIX}/lib/python3.10/site-packages:${PYTHONPATH}"
RUN mkdir -p /data && chmod a+rwX /data

WORKDIR /
RUN echo "${DHCP_PREFIX}/lib" >> /etc/ld.so.conf.d/0-dhcp-pipeline.conf && \
    echo "${DHCP_PREFIX}/lib/mirtk" >> /etc/ld.so.conf.d/0-dhcp-pipeline.conf && \
    echo "${FSLDIR}/lib" >> /etc/ld.so.conf.d/999-fsldir.conf

# Install basic tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    export DEBIAN_FRONTEND=noninteractive APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 && \
    apt-get update -q && \
    apt-get install -yq --no-install-recommends \
        bc \
        bsdextrautils \
        ca-certificates \
        curl \
        dc \
        fd-find \
        git \
        git-lfs \
        gpg \
        gpg-agent \
        gzip \
        less \
        libelf1 \
        libexpat1 \
        libfreetype6 \
        libftgl2 \
        libgl1 \
        libglu1-mesa \
        liblz4-1 \
        libosmesa6 \
        libqt5concurrent5 \
        libqt5core5a \
        libqt5gui5 \
        libqt5network5 \
        libqt5test5 \
        libqt5xml5 \
        libquazip5-1 \
        libx11-6 \
        make \
        moreutils \
        nano \
        parallel \
        patch \
        ripgrep \
        tar \
        time \
        tree \
        unzip \
        wget \
        zlib1g && \
        rm -rf /var/lib/apt/lists/*

# Install Python:
RUN --mount=type=cache,target=/tmp/mamba-cache,sharing=locked \
    export CONDA_PKGS_DIRS=/tmp/mamba-cache CI=1 && \
    micromamba create --yes --verbose --prefix "${FSLDIR}" -c intel intel::python && \
    micromamba install --yes --verbose --prefix "${FSLDIR}" --channel intel --channel https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public --channel conda-forge fsl-avwutils==2209.0 fsl-flirt==2111.0 fsl-bet2==2111.0

# == BUILDER SETUP ==
FROM base AS builder
LABEL stage=builder

ARG BUILD_WITH_CUDA

# Install build tools
WORKDIR /opt/build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    export DEBIAN_FRONTEND=noninteractive APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 && \
    . /etc/os-release && \
    test -f /usr/share/doc/kitware-archive-keyring/copyright || wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${UBUNTU_CODENAME} main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB | gpg --dearmor > /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main " > /etc/apt/sources.list.d/oneAPI.list && \
    apt-get update -q && \
    apt-get install -yq --no-install-recommends cmake && \
    cmake_dir="$(find /usr/share -maxdepth 1 -maxdepth 1 -follow -name 'cmake-*.*' | sort -V | head -n 1 || true)" && \
    [ -n "${cmake_dir:-}" ] || { echo "ERROR: cmake directory not found in /usr/share" >&2; exit 1; } && \
    ln -sv "${cmake_dir}" /opt/build/cmake-dir && \
    apt-get install -yq --no-install-recommends ccache dpkg-dev libc-dev make ninja-build libtool libarchive13 && \
    apt-get install -yq --no-install-recommends \
        intel-oneapi-compiler-dpcpp-cpp \
        intel-oneapi-mkl-devel \
        intel-oneapi-mkl-sycl-devel \
        intel-oneapi-openmp \
        intel-oneapi-tbb-devel \
        intel-oneapi-tlt && \
    rm -rf /var/lib/apt/lists/*

ARG CUDA_PACKAGE
SHELL ["/bin/bash", "-eET", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    export DEBIAN_FRONTEND=noninteractive APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1; \
    [[ -z "${CUDA_PACKAGE:-}" ]] && [[ "${BUILD_WITH_CUDA:-}" =~ [0-9]+\.[0-9]+ ]] && CUDA_PACKAGE="${CUDA_PACKAGE:-cuda-toolkit-${BASH_REMATCH//./-}}"; \
    if [[ -n "${CUDA_PACKAGE:-}" ]]; then apt-get update -q && apt-get install -yq --no-install-recommends gcc-12 g++-12 libc-dev && apt-get install -yq --no-install-recommends cuda-toolkit-12-4 && rm -rf /var/lib/apt/lists/*; fi

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    export DEBIAN_FRONTEND=noninteractive APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 && \
    apt-get update -q && \
    apt-get install -yq --no-install-recommends \
        freeglut3-dev \
        libarpack2-dev \
        libboost-dev \
        libboost-math-dev \
        libboost-random-dev \
        libcifti-dev \
        libcoarrays-openmpi-dev \
        libdcmtk-dev \
        libdouble-conversion-dev \
        libeigen3-dev \
        libexpat-dev \
        libfftw3-dev \
        libflann-dev \
        libfreetype6-dev \
        libftgl-dev \
        libgdcm-dev \
        libgl-dev \
        libglew-dev \
        libglib2.0-dev \
        libglm-dev \
        libglvnd-dev \
        libglx-dev \
        libgtest-dev \
        libhdf5-dev \
        libjpeg-dev \
        libjsoncpp-dev \
        liblz4-dev \
        libminc-dev \
        libnetcdf-dev \
        libnifti-dev \
        libosmesa6-dev \
        libpng-dev \
        libpng-tools \
        libqt5opengl5-dev \
        libquazip5-dev \
        libqwt-qt5-dev \
        libssl-dev \
        libsuitesparse-dev \
        libxml2-dev \
        mesa-utils \
        qtbase5-dev \
        uuid-dev \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Paths to include in the build environment:
ENV CPATH="${DHCP_PREFIX}/include${CPATH:+:${CPATH}}"
ENV LIBRARY_PATH="${DHCP_PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
ENV PKG_CONFIG_PATH="${DHCP_PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

# Cmake general settings:
ENV CMAKE_PREFIX_PATH="${DHCP_PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
ENV CMAKE_INSTALL_PREFIX="${DHCP_PREFIX}"
ENV CMAKE_BUILD_TYPE="Release"
ENV CMAKE_GENERATOR="Ninja"
ENV CMAKE_COLOR_DIAGNOSTICS=ON
ENV CMAKE_C_COMPILER_LAUNCHER="ccache"
ENV CMAKE_CXX_COMPILER_LAUNCHER="ccache"
ENV CMAKE_CUDA_COMPILER_LAUNCHER="ccache"

# Ccache settings:
ENV CCACHE_DIR="/opt/build/ccache"

# C and C++ compiler settings:
ENV CC="icx"
ENV CXX="icpx"

# Default Intel compiler settings:
ENV INTEL_COMPILER_FLAGS_BASE="-fp-model=precise -fuse-ld=lld"
ENV INTEL_COMPILER_FLAGS_OPT="-O3 -xCORE-AVX2 -axSKYLAKE-AVX512 -qopt-zmm-usage=high"
ENV INTEL_CFLAGS_DEFAULT="${INTEL_COMPILER_FLAGS_BASE} ${INTEL_COMPILER_FLAGS_OPT}"
ENV INTEL_CXXFLAGS_DEFAULT="${INTEL_CFLAGS_DEFAULT}"
ENV __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS:-} -static-intel"

# CMake C and C++ settings (default to Intel compiler settings):
ENV CFLAGS="${INTEL_CFLAGS_DEFAULT}"
ENV CXXFLAGS="${INTEL_CXXFLAGS_DEFAULT}"

# CMake CUDA settings:
ENV CUDACXX="nvcc"
ENV CUDAHOSTCXX="g++-12"
ARG CUDAARCHS="75;86"
ENV CUDAARCHS="${CUDAARCHS}"
ENV CUDAFLAGS="-Xcompiler=-march=x86-64-v3 -Xcompiler=-O3 -Xcompiler=-fuse-ld=lld"

# File to source to set up the build environment:
COPY --link parameters/compilervars.sh /opt/build/compilervars.sh
ENV BASH_ENV=/opt/build/compilervars.sh
ENTRYPOINT ["/bin/bash"]
SHELL ["/bin/bash", "-eET", "-o", "pipefail", "-c"]

# == BUILD PROCESS ==

ARG USE_GPU=0

FROM builder AS build-vtk
LABEL stage=build-vtk

# Get VTK source code and configure the build
WORKDIR /opt/build/vtk

# release branch on 2024-06-17T05:29:05PDT:
ADD --keep-git-dir=true https://gitlab.kitware.com/vtk/vtk.git#70fdc0697abe321a727e35b315f2afc599ce7dc4 src

# Configure VTK build
WORKDIR /opt/build/vtk/build

ARG USE_GPU="${BUILD_WITH_CUDA+1}"
ARG VTK_USE_VTKM=0
ARG VTK_USE_GPU="${USE_GPU:-0}"
ARG VTK_VTKM_FLAGS="-DVTK_ALL_NEW_OBJECT_FACTORY=ON -DVTK_ENABLE_VTKM_OVERRIDES=ON -DVTK_MODULE_ENABLE_VTK_AcceleratorsVTKmCore=WANT -DVTK_MODULE_ENABLE_VTK_AcceleratorsVTKmDataModel=WANT -DVTK_MODULE_ENABLE_VTK_AcceleratorsVTKmFilters=WANT -D VTKm_ENABLE_MPI=OFF -D VTKm_ENABLE_RENDERING=OFF -DVTKm_ENABLE_TBB=ON -DVTKm_ENABLE_TESTING=OFF"
ARG VTK_GPU_FLAGS="-DVTK_USE_CUDA=ON -DVTKm_ENABLE_CUDA=ON ${VTK_VTKM_FLAGS}"
RUN --mount=type=cache,target=/opt/build/ccache \
    if [ "${VTK_USE_GPU:-0}" = 1 ]; then VTK_USE_VTKM=0; addFlags="${addFlags:-} ${VTK_GPU_FLAGS:-}"; fi; \
    if [ "${VTK_USE_VTKM:-0}" = 1 ]; then addFlags="${addFlags:-} ${VTK_VTKM_FLAGS:-}"; fi; \
    cmake \
        -D BUILD_SHARED_LIBS=ON \
        -D BUILD_TESTING=OFF \
        -D CMAKE_CXX_STANDARD=17 \
        -D VTK_ENABLE_REMOTE_MODULES=OFF \
        -D VTK_GROUP_ENABLE_Imaging=WANT \
        -D VTK_GROUP_ENABLE_MPI=DONT_WANT \
        -D VTK_GROUP_ENABLE_Qt=DONT_WANT \
        -D VTK_GROUP_ENABLE_Rendering=DONT_WANT \
        -D VTK_GROUP_ENABLE_StandAlone=DONT_WANT \
        -D VTK_GROUP_ENABLE_Views=DONT_WANT \
        -D VTK_GROUP_ENABLE_Web=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonDataModel=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonExecutionModel=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonMath=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonTransforms=WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsChemistry=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsChemistryOpenGL2=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsMicroscopy=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsParallelChemistry=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_fides=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersExtraction=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersFlowPaths=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeneral=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeometry=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersHybrid=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersModeling=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersOpenTURNS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallel=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallelMPI=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSMP=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSources=WANT \
        -D VTK_MODULE_ENABLE_VTK_GeovisCore=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GeovisGDAL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQt=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQtQuick=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQtSQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingStencil=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOADIOS2=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOAMR=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCesium3DTiles=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCGNSReader=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOChemistry=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCityGML=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOCONVERGECFD=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOFFMPEG=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGDAL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGeoJSON=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGeometry=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOImage=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOInfovis=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOIOSS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLAS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLegacy=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLSDyna=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMotionFX=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMovie=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMPIImage=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMPIParallel=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMySQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOODBC=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOOggTheora=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallel=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallelXML=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPDAL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPLY=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPostgreSQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOSQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOVideo=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOXML=WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelDIY=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelMPI4Py=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelMPI=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_PythonInterpreter=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingExternal=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingFreeTypeFontConfig=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingOpenVR=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebCore=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebGLExporter=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebPython=DONT_WANT \
        -D VTK_MODULE_USE_EXTERNAL_VTK_zlib=ON \
        -D VTK_SMP_ENABLE_TBB=ON \
        -D VTK_SMP_IMPLEMENTATION_TYPE=TBB \
        -D VTK_USE_X=OFF \
        -D VTK_WRAP_PYTHON=ON \
        ${addFlags:-} \
    ../src

# Build VTK Accelerators prerequisites
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build . -t CommonComputationalGeometry CommonCore CommonDataModel CommonExecutionModel CommonMath CommonMisc CommonSystem CommonTransforms FiltersCore FiltersGeneral FiltersGeometry FiltersVerdict ImagingCore

ARG CUDA_NCPU=1
RUN --mount=type=cache,target=/opt/build/ccache \
    if [ "${VTK_USE_GPU:-0}" = "1" ]; then export CMAKE_BUILD_PARALLEL_LEVEL="${CUDA_NCPU}"; cmake --build . -t vtkm_cont/cuda/all AcceleratorsVTKmCore AcceleratorsVTKmDataModel AcceleratorsVTKmFilters; fi

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-vtk AS build-itk
LABEL stage=build-itk

ARG USE_GPU
ARG ITK_USE_GPU="${USE_GPU:-0}"
ARG ITK_GPU_FLAGS="-DITK_USE_GPU=ON -DModule_ITKGPUAnisotropicSmoothing=ON -DModule_ITKGPUCommon=ON -DModule_ITKGPUImageFilterBase=ON -DModule_ITKGPUPDEDeformableRegistration=OONN -DModule_ITKGPURegistrationCommon=ON -DModule_ITKGPUSmoothing=ON -DModule_ITKGPUThresholding=ON"
WORKDIR /opt/build/itk
# release branch on 2024-06-20T05:29:05PDT:
ADD --keep-git-dir=true --link https://github.com/InsightSoftwareConsortium/ITK.git#61af74531b44553586bff1de1399a9821d620fe2 src
RUN sed --in-place 's/DMKL_ILP64/DMKL_LP64/g;s/ilp64/lp64/g' src/CMake/FindFFTW.cmake && \
    sed --in-place -E '/(set|SET).*(c_and_cxx_flags|C_AND_CXX_FLAGS).*InstructionSetOptimizationFlags/d' src/CMake/ITKSetStandardCompilerFlags.cmake

WORKDIR /opt/build/itk/build
RUN --mount=type=cache,target=/opt/build/ccache \
    if [ "${ITK_USE_GPU:-0}" = 1 ]; then addFlags="${ITK_GPU_FLAGS:-} -DOpenCL_INCLUDE_DIR=\"${CMPLR_ROOT}/include/sycl\""; fi; \
    cmake \
        -D BUILD_DOCUMENTATION=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_SHARED_LIBS=ON \
        -D BUILD_TESTING=OFF \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_CXX_STANDARD_REQUIRED=ON \
        -D ITK_USE_KWSTYLE=OFF \
        -D ITK_USE_MKL=ON \
        -D ITK_USE_TBB=ON \
        -D ITK_USE_SYSTEM_EIGEN=ON \
        -D ITK_USE_SYSTEM_ZLIB=ON \
        -D ITKGroup_Compatibility=OFF \
        -D ITKGroup_Core=ON \
        -D ITKGroup_Filtering=OFF \
        -D ITKGroup_Numerics=OFF \
        -D TKGroup_ThirdParty=OFF \
        -D ITKGroup_Registration=OFF \
        -D ITKGroup_Remote=OFF \
        -D ITKGroup_Segmentation=ON \
        -D ITKGroup_Video=OFF \
        -D Module_ITKTBB=ON \
        ${addFlags:-} \
    ../src

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-itk AS build-mirtk-src
LABEL stage=build-mirtk

ARG USE_GPU
ARG MIRTK_USE_GPU="${USE_GPU:-0}"
ARG MIRTK_GPU_FLAGS=""

WORKDIR /opt/build/mirtk
ADD --link --keep-git-dir=true https://github.com/BioMedIA/MIRTK.git#973ce2fe3f9508dec68892dbf97cca39067aa3d6 src
ADD --link --keep-git-dir=true https://github.com/MIRTK/DrawEM.git#37a94ad629f6525675f06a45bed83bad04b544a5 drawem-src
ADD --link https://biomedic.doc.ic.ac.uk/brain-development/downloads/dHCP/atlases-dhcp-structural-pipeline-v1.zip atlases-dhcp-structural-pipeline-v1.zip

RUN rm -rfv src/Packages/DrawEM/* && \
    cp -rv drawem-src/* src/Packages/DrawEM/

COPY --link src/ThirdParty/mirtk/Packages/DrawEM/ThirdParty/ANTs/antsCommandLineOption.h src/Packages/DrawEM/ThirdParty/ANTs/antsCommandLineOption.h
RUN sed --in-place 's/CXX-11/CXX-17/g' src/CMakeLists.txt

FROM build-mirtk-src AS build-mirtk
WORKDIR /opt/build/mirtk/build

RUN --mount=type=cache,target=/opt/build/ccache \
   export \
        CFLAGS="-fuse-ld=ld -fp-model=precise -xCORE-AVX2 -ipo" CXXFLAGS="-fuse-ld=ld -fp-model=precise -xCORE-AVX2 -ipo" && \
    cmake -Wno-dev \
        -D CMAKE_INSTALL_PREFIX="${DHCP_PREFIX}" \
        -D CMAKE_CXX_STANDARD=17 \
        -D MODULE_Common=ON \
        -D MODULE_Deformable=ON \
        -D MODULE_DrawEM=ON \
        -D MODULE_IO=ON \
        -D MODULE_Image=ON \
        -D MODULE_Mapping=OFF \
        -D MODULE_Numerics=ON \
        -D MODULE_PointSet=ON \
        -D MODULE_Registration=ON \
        -D MODULE_Scripting=OFF \
        -D MODULE_Transformation=ON \
        -D MODULE_Viewer=OFF \
        -D WITH_EIGEN3=ON \
        -D WITH_FLANN=ON \
        -D WITH_ITK=ON \
        -D WITH_MATLAB=OFF \
        -D WITH_NiftiCLib=ON \
        -D WITH_TBB=ON \
        -D WITH_VTK=ON \
        ${addFlags:-} \
    ../src && \
    mv ../atlases-dhcp-structural-pipeline-v1.zip Packages/DrawEM/atlases/src/

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build .


RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install . && \
    cp -vb lib/mirtk/tools/N4 "${DHCP_PREFIX}/lib/mirtk/tools/N4" && \
    ln -sfbv "${DHCP_PREFIX}/lib/mirtk/tools/N4" "${DHCP_PREFIX}/bin/N4"

WORKDIR /opt/build/mirtk/src/Packages/DrawEM
RUN mkdir -p "${DRAWEMDIR}" && \
    cp -rv atlases "${DRAWEMDIR}" && \
    cp -rv label_names "${DRAWEMDIR}" && \
    cp -rv parameters "${DRAWEMDIR}" && \
    cp -rv scripts "${DRAWEMDIR}" && \
    git config --worktree --unset-all core.worktree && \
    cp -rv /opt/build/mirtk/src/.git/modules/Packages/DrawEM "${DRAWEMDIR}/.git"

FROM build-mirtk AS build-workbench
LABEL stage=build-workbench

WORKDIR /opt/build/workbench
ADD --link --keep-git-dir=true https://github.com/Washington-University/workbench.git#5b3b27ac93e238abd45f43f40a352767657b620e src
COPY --link src/ThirdParty/workbench/src/Nifti/NiftiHeader.cxx src/src/Nifti/NiftiHeader.cxx

RUN cd src/src/CZIlib/CZI && ln -sv eigen Eigen
RUN cp /usr/share/quazip/QuaZip5Config.cmake /opt/build/cmake-dir/Modules/FindQuaZip.cmake

RUN sed --in-place -E 's/\.\*icpc\$/ic[px]c$/g; s/\(\s*CMAKE_COMPILER_IS_GNUCC\s+OR\s+CLANG_FLAG\s*\)/TRUE/g; /ADD_SUBDIRECTORY.*\(\s*(Desktop|Tests)\s*\)/d' src/src/CMakeLists.txt
RUN sed --in-place 's#-openmp-link=static#-fiopenmp -fopenmp-targets=spir64 -fsycl $ENV{MKLROOT}/lib/libmkl_sycl.a -Wl,--start-group \$ENV{MKLROOT}/lib/libmkl_intel_lp64.a $ENV{MKLROOT}/lib/libmkl_intel_thread.a $ENV{MKLROOT}/lib/libmkl_core.a -Wl,--end-group -liomp5 -lsycl -lOpenCL -lstdc++ -lpthread -lm -ldl#g' src/src/CMakeLists.txt

WORKDIR /opt/build/workbench/build
RUN --mount=type=cache,target=/opt/build/ccache \
    export \
        CFLAGS="${CFLAGS//-xCORE-AVX2/} -I/opt/build/workbench/src/src/CZIlib/CZI" \
        CXXFLAGS="${CXXFLAGS//-xCORE-AVX2/} -I/opt/build/workbench/src/src/CZIlib/CZI -Wno-inconsistent-missing-override -Wno-c++11-narrowing -Wno-deprecated-declarations" && \
    cmake \
            -D BUILD_DOCUMENTATION=OFF \
            -D BUILD_EXAMPLES=OFF \
            -D CMAKE_CXX_STANDARD=17 \
            -D CMAKE_CXX_STANDARD_REQUIRED=ON \
            -D WORKBENCH_USE_QT5_QOPENGL_WIDGET=TRUE \
            -D WORKBENCH_USE_QT5=TRUE \
            -D WORKBENCH_USE_SIMD=TRUE \
            -D WORKBENCH_MESA_DIR=/usr \
            -D WORKBENCH_INCLUDE_HELP_HTML_RESOURCES=FALSE \
        ../src/src

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build . -t dot && \
    export __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS:-} ${INTEL_COMPILER_FLAGS_OPT:-}" && \
    cmake --build . -t CommandLine/all

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-workbench AS build-sphericalmesh
LABEL stage=build-sphericalmesh

WORKDIR /opt/build/sphericalmesh
COPY --link src/ThirdParty/SphericalMesh src

WORKDIR /opt/build/sphericalmesh/build
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake ../src && \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install . && \
    install -vpDm755 bin/* "${DHCP_PREFIX}/bin"

FROM build-sphericalmesh AS build-pipeline
LABEL stage=build-pipeline

WORKDIR /opt/build/pipeline-applications/src
COPY --link applications applications
COPY --link CMakeLists.txt CMakeLists.txt

WORKDIR /opt/build/pipeline-applications/build
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake ../src && \
    cmake --build . && \
    cmake --install . && \
    install -v -Dm755 bin/* "${DHCP_PREFIX}/bin"

# == FINAL IMAGE ==

FROM base AS final
LABEL stage=final

RUN \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so libblas.so-x86_64-linux-gnu "${FSLDIR}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so.3 libblas.so.3-x86_64-linux-gnu "${FSLDIR}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so liblapack.so-x86_64-linux-gnu "${FSLDIR}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so.3 liblapack.so.3-x86_64-linux-gnu "${FSLDIR}/lib/libmkl_rt.so" 50 && \
    ldconfig

WORKDIR /
COPY --link --from=build-pipeline "${DHCP_PREFIX}" "${DHCP_PREFIX}"

WORKDIR "${DHCP_PREFIX}/src"
COPY --link dhcp-pipeline.sh version .
COPY --link parameters parameters
COPY --link scripts scripts
RUN ln -sv "${DHCP_PREFIX}/share/DrawEM/atlases" "${DHCP_PREFIX}/src/atlases" && ln -sv "${DHCP_PREFIX}/src/dhcp-pipeline.sh" "${DHCP_PREFIX}/bin/dhcp-pipeline"
RUN ldconfig
WORKDIR /data
ENV DHCP_DEBUG=1
ENV TIME="user=%U sys=%S wall=%E cpu=%P %% mmax=%MK mavg=%kK i=%I o=%O swap=%W # %C"
ENV TSFORMAT="%FT%H:%M:%S"
ENV __DHCP_DEBUG_PATH_GLOB="/opt/dhcp/*"
ENV BASH_ENV="${DHCP_PREFIX}/src/parameters/debug.bash"
ENTRYPOINT ["/opt/dhcp/bin/dhcp-pipeline"]
CMD ["-help"]
