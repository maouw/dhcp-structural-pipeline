# syntax=docker/dockerfile:1
## Build Docker image for execution of dhcp pipelines within a Docker
## container with all modules and applications available in the image

# == BASE IMAGE ==
FROM mambaorg/micromamba:jammy AS base

USER root

# Global system-level config
ENV TZ=UTC \
    LANGUAGE=en_US:en \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1

# Force apt to leave downloaded binaries in /var/cache/apt (massively speeds up Docker builds)
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Acquire::Queue-Mode: Queuing mode; Queue-Mode can be one of host or access which determines how APT parallelizes outgoing connections. host means that one connection per target host will be opened, access means that one connection per URI type will be opened.
RUN echo 'Acquire::Queue-Mode "host";' > /etc/apt/apt.conf.d/99queue

# Set up basic environment
ENV DHCP_PREFIX="/opt/dhcp"
ENV FSLDIR="${DHCP_PREFIX}/fsl"
ENV PATH="${DHCP_PREFIX}/bin:${FSLDIR}/bin:${DHCP_PREFIX}/bin:${PATH}"
ENV ONEAPI_ROOT="/opt/intel/oneapi"

WORKDIR "${DHCP_PREFIX}"
RUN mkdir -p bin etc lib libexec share src && chmod -R a+rX "${DHCP_PREFIX}" && echo "${DHCP_PREFIX}/lib" > /etc/ld.so.conf.d/0-dhcp-pipeline.conf

# Install basic tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -q && \
    apt-get install -yq --no-install-recommends \
        bat \
        bc \
        dc \
        ca-certificates \
        curl \
        fd-find \
        git \
        git-lfs \
        gpg \
        gpg-agent \
        gzip \
        less \
        make \
        moreutils \
        patch \
        parallel \
        nano \
        ripgrep \
        tar \
        tree \
        time \
        unzip \
        wget

# Install Python:
RUN micromamba create --yes --verbose --prefix "${FSLDIR}" -c intel intel::python>=3.10 && micromamba clean --yes --all

# == BUIDER SETUP ==
FROM base AS builder-base
# Install build tools
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /opt/build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    . /etc/os-release && \
    test -f /usr/share/doc/kitware-archive-keyring/copyright || wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${UBUNTU_CODENAME} main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt-get update -q -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
        -o "Dir::Etc::sourcelist=/etc/apt/sources.list.d/kitware.list" && \
    apt-get install -yq --no-install-recommends cmake && \
    cmake_dir="$(find /usr/share -maxdepth 1 -maxdepth 1 -follow -name 'cmake-*.*' | sort -V | head -n 1 || true)" && \
    [ -n "${cmake_dir:-}" ] || { echo "ERROR: cmake directory not found in /usr/share" >&2; exit 1; } && \
    ln -sv "${cmake_dir}" /opt/build/cmake-dir

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends gcc-12 g++-12 libc-dev && \
    apt-get install -yq --no-install-recommends ccache dpkg-dev make ninja-build libtool libarchive13

FROM builder-base AS builder-cuda
# Install CUDA build tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    . /etc/os-release && \
    curl -fsSL -o /tmp/cuda-keyring.deb \
        "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${VERSION_ID%.*}${VERSION_ID#*.}/$(uname -p)/cuda-keyring_1.1-1_all.deb" && \
    dpkg -i /tmp/cuda-keyring.deb && \
    rm -f /tmp/cuda-keyring.deb && \
    apt-get update -q -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
        -o "Dir::Etc::sourcelist=/etc/apt/sources.list.d/cuda-ubuntu${VERSION_ID%.*}${VERSION_ID#*.}-$(uname -p).list" && \
    apt-get install -yq --no-install-recommends cuda-minimal-build-12-4

ENV PATH="/usr/local/cuda-12/bin:${PATH}"

FROM builder-cuda AS builder-intel
# Install Intel oneAPI build tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB | gpg --dearmor > /usr/share/keyrings/intel-oneapi-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main " > /etc/apt/sources.list.d/oneAPI.list && \
    apt-get update -q -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
        -o "Dir::Etc::sourcelist=/etc/apt/sources.list.d/oneAPI.list"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends intel-oneapi-compiler-dpcpp-cpp-and-cpp-classic && \
    ( . "${ONEAPI_ROOT}/setvars.sh" && cd "${ONEAPI_ROOT}/compiler" && ln -sv "$(basename "${CMPLR_ROOT}")" classic )

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends \
        intel-oneapi-compiler-dpcpp-cpp \
        intel-oneapi-ipp-devel \
        intel-oneapi-mkl-devel \
        intel-oneapi-openmp \
        intel-oneapi-tbb-devel \
        intel-oneapi-tlt

RUN MKLROOT="${ONEAPI_ROOT:-/opt/intel/oneapi}/mkl/latest" && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 --slave /usr/bin/g++ g++ /usr/bin/g++-12 --slave /usr/bin/gcov gcov /usr/bin/gcov-12 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so    libblas.so-x86_64-linux-gnu      "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so.3  libblas.so.3-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so liblapack.so-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so.3 liblapack.so.3-x86_64-linux-gnu  "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-ccache-symlinks

FROM builder-intel AS builder

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
ENV INTEL_CFLAGS_DEFAULT="${INTEL_COMPILER_FLAGS_BASE} -DEIGEN_USE_MKL_ALL -O3 -xCORE-AVX2 -axSKYLAKE-AVX512 -qopt-zmm-usage=high"
ENV INTEL_CXXFLAGS_DEFAULT="${INTEL_CFLAGS_DEFAULT}"

# CMake C and C++ settings (default to Intel compiler settings):
ENV CFLAGS="${INTEL_CFLAGS_DEFAULT}"
ENV CXXFLAGS="${INTEL_CXXFLAGS_DEFAULT}"

# CMake CUDA settings:
ENV CUDACXX="nvcc"
ENV CUDAHOSTCXX="g++-12"
ENV CUDAARCHS="75"
ENV CUDAFLAGS="-Xcompiler=-DEIGEN_USE_MKL_ALL -Xcompiler=-march=x86-64-v3 -Xcompiler=-O3 -Xcompiler=-fuse-ld=lld"

# File to source to set up the build environment:
COPY parameters/compilervars.sh /opt/build/compilervars.sh
ENV BASH_ENV=/opt/build/compilervars.sh
ENTRYPOINT ["/bin/bash"]
SHELL ["/bin/bash", "-eE", "-o", "pipefail", "-c"]

# == BUILD PROCESS ==

# Install libs:
FROM builder AS builder-libs
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
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
        zlib1g-dev

FROM builder-libs AS build-vtk-src
# Get VTK source code and configure the build
WORKDIR /opt/build/vtk
ADD --keep-git-dir=true https://gitlab.kitware.com/vtk/vtk.git#release src
RUN rm -rf src/ThirdParty/vtkm/vtkvtkm/vtk-m
ADD --keep-git-dir=true https://gitlab.kitware.com/vtk/vtk-m.git#release src/ThirdParty/vtkm/vtkvtkm/vtk-m

FROM build-vtk-src AS build-vtk-config
# Configure VTK build
WORKDIR /opt/build/vtk/build
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake \
        -D CMAKE_CXX_STANDARD=17 \
        -D BUILD_SHARED_LIBS=ON \
        -D BUILD_TESTING=OFF \
        -D VTK_ENABLE_REMOTE_MODULES=OFF \
        -D VTK_ENABLE_VTKM_OVERRIDES=ON \
        -D VTK_ENABLE_WRAPPING=ON \
        -D VTK_GROUP_ENABLE_Qt=DONT_WANT \
        -D VTK_GROUP_ENABLE_Rendering=DONT_WANT \
        -D VTK_GROUP_ENABLE_StandAlone=DONT_WANT \
        -D VTK_GROUP_ENABLE_Views=DONT_WANT \
        -D VTK_GROUP_ENABLE_MPI=DONT_WANT \
        -D VTK_GROUP_ENABLE_Web=DONT_WANT \
        -D VTK_GROUP_ENABLE_Imaging=WANT \
        -D VTK_MODULE_USE_EXTERNAL_VTK_eigen=ON \
        -D VTK_SMP_ENABLE_TBB=ON \
        -D VTK_SMP_IMPLEMENTATION_TYPE=TBB \
        -D VTK_USE_CUDA=ON \
        -D VTK_USE_X=OFF \
        -D VTK_WRAP_JAVA=OFF \
        -D VTK_WRAP_PYTHON=ON \
        -D VTKm_ENABLE_CUDA=ON \
        -D VTKm_ENABLE_DEVELOPER_FLAGS=OFF \
        -D VTKm_ENABLE_MPI=OFF \
        -D VTKm_ENABLE_RENDERING=OFF \
        -D VTKm_ENABLE_TBB=ON \
        -D VTKm_ENABLE_TESTING=OFF \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmDataModel=WANT \
        -D VTK_MODULE_ENABLE_VTK_AcceleratorsVTKmFilters=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonDataModel=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonExecutionModel=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonMath=WANT \
        -D VTK_MODULE_ENABLE_VTK_CommonTransforms=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersExtraction=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersFlowPaths=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeneral=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersGeometry=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersHybrid=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersModeling=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallel=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSMP=WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersSources=WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_ImagingStencil=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOGeometry=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOImage=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLegacy=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallel=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOParallelXML=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPLY=WANT \
        -D VTK_MODULE_ENABLE_VTK_IOXML=WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelCore=WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsChemistry=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsChemistryOpenGL2=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsMicroscopy=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_DomainsParallelChemistry=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_fides=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersOpenTURNS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallelDIY2=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_FiltersParallelMPI=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GeovisCore=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GeovisGDAL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQt=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQtQuick=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_GUISupportQtSQL=DONT_WANT \
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
        -D VTK_MODULE_ENABLE_VTK_IOInfovis=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOIOSS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLAS=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOLSDyna=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMotionFX=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMovie=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMPIImage=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMPIParallel=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOMySQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOODBC=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOOggTheora=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPDAL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOPostgreSQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOSQL=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_IOVideo=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelDIY=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelMPI=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_ParallelMPI4Py=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_PythonInterpreter=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingExternal=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingFreeTypeFontConfig=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_RenderingOpenVR=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebCore=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebGLExporter=DONT_WANT \
        -D VTK_MODULE_ENABLE_VTK_WebPython=DONT_WANT \
    ../src


FROM build-vtk-config AS build-vtk-pre
# Build VTK Accelerators prerequisites
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build . -t CommonComputationalGeometry CommonCore CommonDataModel CommonExecutionModel CommonMath CommonMisc CommonSystem CommonTransforms FiltersCore FiltersGeneral FiltersGeometry FiltersVerdict ImagingCore

FROM build-vtk-pre AS build-vtk-cuda
# Build VTK Accelerators (using single-threaded build for memory issues and mu

ARG CUDA_NCPU=1
RUN --mount=type=cache,target=/opt/build/ccache \
    export CMAKE_BUILD_PARALLEL_LEVEL="${CUDA_NCPU:-1}" && \
    cmake --build . -t vtkm_cont

RUN --mount=type=cache,target=/opt/build/ccache \
    export CMAKE_BUILD_PARALLEL_LEVEL="${CUDA_NCPU:-1}" && \
    cmake --build . -t AcceleratorsVTKmCore

RUN --mount=type=cache,target=/opt/build/ccache \
    export CMAKE_BUILD_PARALLEL_LEVEL="${CUDA_NCPU:-1}" && \
    cmake --build . -t AcceleratorsVTKmDataModel

RUN --mount=type=cache,target=/opt/build/ccache \
    export CMAKE_BUILD_PARALLEL_LEVEL="${CUDA_NCPU:-1}" && \
    cmake --build . -t  AcceleratorsVTKmFilters

FROM build-vtk-pre AS build-vtk
# Build VTK

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-vtk AS build-itk-src
WORKDIR /opt/build/itk
ADD --keep-git-dir=true https://github.com/InsightSoftwareConsortium/ITK.git#release src
RUN sed --in-place 's/DMKL_ILP64/DMKL_LP64/g;s/ilp64/lp64/g' src/CMake/FindFFTW.cmake && \
    sed --in-place -E '/(set|SET).*(c_and_cxx_flags|C_AND_CXX_FLAGS).*InstructionSetOptimizationFlags/d' src/CMake/ITKSetStandardCompilerFlags.cmake

FROM build-itk-src AS build-itk-config
WORKDIR /opt/build/itk/build
RUN --mount=type=cache,target=/opt/build/ccache \
    addWFlags="-Wno-deprecated -Wno-unused-command-line-argument" && \
    export CFLAGS="$(echo "${CFLAGS} ${addWFlags}" | sed -E 's/-DEIGEN_USE_MKL\w+//; s/\s+/ /g')" && \
    export CXXFLAGS="$(echo "${CXXFLAGS} ${addWFlags}" | sed -E 's/-DEIGEN_USE_MKL\w+//; s/\s+/ /g')" && \
    cmake \
        -D BUILD_DOCUMENTATION=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_SHARED_LIBS=ON \
        -D BUILD_TESTING=OFF \
        -D ITK_USE_GPU=ON \
        -D ITK_USE_KWSTYLE=OFF \
        -D ITK_USE_MKL=ON \
        -D ITK_USE_SYSTEM_LIBRARIES=ON \
        -D ITK_USE_TBB=ON \
        -D ITKGroup_Compatibility=ON \
        -D ITKGroup_Core=ON \
        -D ITKGroup_Filtering=ON \
        -D ITKGroup_Numerics=ON \
        -D ITKGroup_Registration=ON \
        -D ITKGroup_Remote=OFF \
        -D ITKGroup_Segmentation=ON \
        -D ITKGroup_Video=OFF \
        -D Module_ITKGPUAnisotropicSmoothing=ON \
        -D Module_ITKGPUCommon=ON \
        -D Module_ITKGPUImageFilterBase=ON \
        -D Module_ITKGPUPDEDeformableRegistration=ON \
        -D Module_ITKGPURegistrationCommon=ON \
        -D Module_ITKGPUSmoothing=ON \
        -D Module_ITKGPUThresholding=ON \
        -D OpenCL_INCLUDE_DIR="${CMPLR_ROOT}/include/sycl" \
    ../src

FROM build-itk-config AS build-itk

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-itk AS build-mirtk-src
WORKDIR /opt/build/mirtk
ADD --link --keep-git-dir=true https://github.com/BioMedIA/MIRTK.git#973ce2fe3f9508dec68892dbf97cca39067aa3d6 src
RUN cd src && git submodule update --init --remote --recursive
COPY src/ThirdParty/mirtk/Packages/DrawEM/ThirdParty/ANTs/antsCommandLineOption.h src/Packages/DrawEM/ThirdParty/ANTs/antsCommandLineOption.h

FROM build-mirtk-src AS build-mirtk-config
WORKDIR /opt/build/mirtk/build
RUN --mount=type=cache,target=/opt/build/ccache \
    export LDFLAGS="-Wl,--push-state,--as-needed -llz4 -Wl,--pop-state" && \
    cmake -Wno-dev \
        -D CMAKE_INSTALL_PREFIX="${DHCP_PREFIX}" \
        -D MODULE_Common=ON \
        -D MODULE_Deformable=ON \
        -D MODULE_DrawEM=ON \
        -D MODULE_IO=ON \
        -D MODULE_Image=ON \
        -D MODULE_Mapping=ON \
        -D MODULE_Numerics=ON \
        -D MODULE_PointSet=ON \
        -D MODULE_Registration=ON \
        -D MODULE_Scripting=ON \
        -D MODULE_Transformation=ON \
        -D MODULE_Viewer=OFF \
        -D WITH_EIGEN3=ON \
        -D WITH_FLANN=ON \
        -D WITH_ITK=ON \
        -D WITH_MATLAB=OFF \
        -D WITH_NiftiCLib=ON \
        -D WITH_TBB=ON \
        -D WITH_VTK=ON \
    ../src

FROM build-mirtk-config AS build-mirtk

RUN --mount=type=cache,target=/opt/build/ccache \
    export __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS:-} -Wl,--start-group ${MKLROOT}/lib/libmkl_intel_lp64.a ${MKLROOT}/lib/libmkl_tbb_thread.a ${MKLROOT}/lib/libmkl_core.a -Wl,--end-group -L${TBBROOT}/lib/ -ltbb -lstdc++ -lpthread -lm -ldl -static-intel" && \
    cmake --build . -t lib/libMIRTKlbfgs.a && \
    llvm-ranlib lib/libMIRTKlbfgs.a && \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

WORKDIR /opt/build/mirtk/src/Packages/DrawEM
RUN DRAWEMDIR="${DHCP_PREFIX}/share/DrawEM" && \
    mkdir -p "${DRAWEMDIR}" && \
    cp -Rv atlases "${DRAWEMDIR}" && \
    cp -R label_names "${DRAWEMDIR}" && \
    cp -R parameters "${DRAWEMDIR}" && \
    cp -R scripts "${DRAWEMDIR}" && \
    git config --worktree --unset-all core.worktree && \
    cp -R /opt/build/mirtk/src/.git/modules/Packages/DrawEM "${DRAWEMDIR}/.git"

ENV LD_LIBRARY_PATH="${DHCP_PREFIX}/lib/mirtk:${LD_LIBRARY_PATH}"

FROM build-mirtk AS build-workbench-src
WORKDIR /opt/build/workbench
ADD --link --keep-git-dir=true https://github.com/Washington-University/workbench.git#5b3b27ac93e238abd45f43f40a352767657b620e src
COPY src/ThirdParty/workbench/src/Nifti/NiftiHeader.cxx src/src/Nifti/NiftiHeader.cxx

RUN sed --in-place -E 's/\.\*icpc\$/ic[px]c$/g; s/\(\s*CMAKE_COMPILER_IS_GNUCC\s+OR\s+CLANG_FLAG\s*\)/TRUE/g; s/-openmp-link=static/-qmkl=parallel -fiopenmp -fopenmp-targets=spir64 -lstdc++/g; s/static-intel//g' src/src/CMakeLists.txt

RUN cd src/src/CZIlib/CZI && ln -sv eigen Eigen
RUN cp /usr/share/quazip/QuaZip5Config.cmake /opt/build/cmake-dir/Modules/FindQuaZip.cmake

FROM build-workbench-src AS build-workbench-config

WORKDIR /opt/build/workbench/build
RUN --mount=type=cache,target=/opt/build/ccache \
    addFlags="-UEIGEN_USE_MKL_ALL -DEIGEN_USE_MKL -I/opt/build/workbench/src/src/CZIlib/CZI -ipo -Wno-inconsistent-missing-override -Wno-c++11-narrowing -Wno-deprecated-declarations"  && \
    export CFLAGS="${CFLAGS//-xCORE-AVX2/} ${addFlags}" CXXFLAGS="${CXXFLAGS//-xCORE-AVX2/} ${addFlags}" && \
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

FROM build-workbench-config AS build-workbench
RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --build . -t dot

RUN --mount=type=cache,target=/opt/build/ccache \
    export __INTEL_POST_CFLAGS="-xCORE-AVX2 -axSKYLAKE-AVX512 ${__INTEL_POST_CFLAGS:-} -Wno-inconsistent-missing-override" && \
    cmake --build .

RUN ctest

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install .

FROM build-workbench AS build-sphericalmesh-src
WORKDIR /opt/build/sphericalmesh
COPY src/ThirdParty/SphericalMesh src

FROM  build-sphericalmesh-src AS build-sphericalmesh-config
WORKDIR /opt/build/sphericalmesh/build
RUN --mount=type=cache,target=/opt/build/ccache \
    export CFLAGS="${CFLAGS} -ipo" CXXFLAGS="${CXXFLAGS} -ipo" && \
    cmake ../src

FROM build-sphericalmesh-config AS build-sphericalmesh
RUN --mount=type=cache,target=/opt/build/ccache \
    export CPATH="${DHCP_PREFIX}/include/vtk-9.3:${CPATH}" && \
    cmake --build .

RUN --mount=type=cache,target=/opt/build/ccache \
    cmake --install . && \
    install -vpDm755 bin/* "${DHCP_PREFIX}/bin"

# Install FSL:
FROM build-sphericalmesh AS build-fsl
RUN export CI=1 && \
    micromamba install --yes --verbose --prefix "${FSLDIR}" --channel intel --channel https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public --channel conda-forge fsl-avwutils==2209.0 fsl-flirt==2111.0 fsl-bet2==2111.0 && \
    micromamba clean --yes --all

FROM build-fsl AS build-pipeline-applications
WORKDIR /opt/build/pipeline-applications/src
COPY applications applications
COPY CMakeLists.txt CMakeLists.txt
RUN cp /opt/build/mirtk/build/lib/mirtk/tools/N4 "${DHCP_PREFIX}/lib/mirtk/tools/N4" && \
    ln -sfv "${DHCP_PREFIX}/lib/mirtk/tools/N4" "${DHCP_PREFIX}/bin/N4"

WORKDIR /opt/build/pipeline-applications/build
RUN --mount=type=cache,target=/opt/build/ccache \
    export CFLAGS="${CFLAGS} -ipo" CXXFLAGS="${CXXFLAGS} -ipo" && \
    cmake ../src && \
    cmake --build . && \
    cmake --install . && \
    install -v -Dm755 bin/* "${DHCP_PREFIX}/bin"

FROM build-pipeline-applications AS build-pipeline
WORKDIR "${DHCP_PREFIX}/src"
COPY --chmod=a+rX dhcp-pipeline.sh version .
COPY --chmod=a+rX parameters parameters
COPY --chmod=a+rX scripts scripts
RUN ln -sv "${DHCP_PREFIX}/share/DrawEM/atlases" "${DHCP_PREFIX}/atlases"
RUN cd "$DRAWEMDIR" && git init && git config user.email 'nobody@example.com'; git config user.name 'nobody'; git commit --allow-empty --allow-empty-message --no-verify -m ''

# == FINAL IMAGE ==

FROM base AS final

WORKDIR "${ONEAPI_ROOT}"
COPY --from=build-pipeline "${ONEAPI_ROOT}/compiler/2024.1" "${ONEAPI_ROOT}/compiler/2024.1"
COPY --from=build-pipeline "${ONEAPI_ROOT}/mkl/2024.1" "${ONEAPI_ROOT}/mkl/2024.1"
COPY --from=build-pipeline "${ONEAPI_ROOT}/tbb/2021.12" "${ONEAPI_ROOT}/tbb/2021.12"
COPY --from=build-pipeline "${ONEAPI_ROOT}/tcm" "${ONEAPI_ROOT}/tcm"
COPY --from=build-pipeline "${ONEAPI_ROOT}/etc" "${ONEAPI_ROOT}/etc"
COPY --from=build-pipeline "${ONEAPI_ROOT}/common" "${ONEAPI_ROOT}/common"
COPY --from=build-pipeline "${ONEAPI_ROOT}/setvars.sh" "${ONEAPI_ROOT}/setvars.sh"
COPY --from=build-pipeline /usr /usr
COPY --from=build-pipeline /etc /etc
COPY --from=build-pipeline "${DHCP_PREFIX}" "${DHCP_PREFIX}"

RUN \
    for x in common compiler mkl tbb tcm; do \
        cd "${x}" && ln -sv * latest && cd ..; \
    done


WORKDIR "${DHCP_PREFIX}"
RUN ln -sv "${DHCP_PREFIX}/src/dhcp-pipeline.sh" "${DHCP_PREFIX}/bin/dhcp-pipeline"
RUN rm -rf '=3.10' # Junk

ENV ITK_GLOBAL_DEFAULT_THREADER="tbb"
ENV DRAWEMDIR="${DHCP_PREFIX}/share/DrawEM"
ENV VTK_SMP_BACKEND_IN_USE="${VTK_SMP_BACKEND_IN_USE:-TBB}"
ENV TBBROOT="${ONEAPI_ROOT}/tbb/latest"
ENV MKLROOT="${ONEAPI_ROOT}/mkl/latest"

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
ENV PATH="${DHCP_PREFIX}/bin:${FSLDIR}/bin:/usr/local/cuda-12/bin:${PATH}"

RUN \
    echo "${DHCP_PREFIX}/lib/mirtk" > /etc/ld.so.conf.d/mirtk.conf && \
    echo "${TBBROOT}/lib/intel64/gcc4.8" >> /etc/ld.so.conf.d/1-intel.conf && \
    echo "${MKLROOT}/lib" >> /etc/ld.so.conf.d/1-intel.conf && \
    echo "${ONEAPI_ROOT}/compiler/latest/lib" >> /etc/ld.so.conf.d/1-intel.conf && \
    echo "${ONEAPI_ROOT}/compiler/latest/opt/compiler/lib" >> /etc/ld.so.conf.d/1-intel.conf && \
    ldconfig

RUN \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so    libblas.so-x86_64-linux-gnu      "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so.3  libblas.so.3-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so liblapack.so-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so.3 liblapack.so.3-x86_64-linux-gnu  "${MKLROOT}/lib/libmkl_rt.so" 50 && \
    ldconfig

WORKDIR /data
ENTRYPOINT ["/opt/dhcp/bin/dhcp-pipeline"]
CMD ["-help"]
