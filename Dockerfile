# syntax=docker/dockerfile:1
## Build Docker image for execution of dhcp pipelines within a Docker
## container with all modules and applications available in the image

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


SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
ENV DHCP_PREFIX="/opt/dhcp"
ENV FSLDIR="${DHCP_PREFIX}/fsl"
ENV PATH="${DHCP_PREFIX}/bin:${FSLDIR}/bin:${DHCP_PREFIX}/bin:${PATH}"
ENV ONEAPI_ROOT="/opt/intel/oneapi"
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    <<-EOF

    mkdir -p "${DHCP_PREFIX}"/{bin,etc,lib,libexec,share,src}
    chmod -R a+rX "${DHCP_PREFIX}"
    echo "${DHCP_PREFIX}/lib" > /etc/ld.so.conf.d/0-dhcp-pipeline.conf
    ldconfig

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -yq --no-install-recommends \
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
        moreutils \
        patch \
        nano \
        ripgrep \
        tar \
        tree \
        time \
        unzip \
        wget

    curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB | gpg --dearmor > /usr/share/keyrings/intel-oneapi-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/intel-oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main " > /etc/apt/sources.list.d/oneAPI.list

    apt-get update -q
    apt-get install -yq intel-oneapi-mkl-core intel-oneapi-tbb intel-oneapi-openmp


    MKLROOT="${ONEAPI_ROOT:-/opt/intel/oneapi}/mkl/latest"

    ## update alternatives
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so    libblas.so-x86_64-linux-gnu      "${MKLROOT}/lib/libmkl_rt.so" 50
    update-alternatives --install /usr/lib/x86_64-linux-gnu/libblas.so.3  libblas.so.3-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so liblapack.so-x86_64-linux-gnu    "${MKLROOT}/lib/libmkl_rt.so" 50
    update-alternatives --install /usr/lib/x86_64-linux-gnu/liblapack.so.3 liblapack.so.3-x86_64-linux-gnu  "${MKLROOT}/lib/libmkl_rt.so" 50
    
    # Update dynamic linker
    echo "${ONEAPI_ROOT}/compiler/latest/linux/compiler/lib/intel64_lin" >> /etc/ld.so.conf.d/1-intel.conf
    echo "${ONEAPI_ROOT}/compiler/latest/linux/lib" >> /etc/ld.so.conf.d/1-intel.conf
    echo "${ONEAPI_ROOT}/compiler/latest/linux/lib/x64" >> /etc/ld.so.conf.d/1-intel.conf
    echo "${MKLROOT}/lib/intel64" >> /etc/ld.so.conf.d/1-intel.conf
    echo "${TBBROOT}/lib/intel64/gcc4.8" >> /etc/ld.so.conf.d/1-intel.conf

EOF

RUN micromamba create --yes --verbose --prefix "${FSLDIR}" -c intel intel::python>=3.10 && micromamba clean --yes --all

FROM base AS builder-base
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /opt/build
COPY src/build-src/fix-cmake-intel-openmp.sh /opt/build/fix-cmake-intel-openmp.sh
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq gcc-12 g++-12 && \
    apt-get install -yq --no-install-recommends build-essential make ninja-build libtool libarchive13

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 --slave /usr/bin/g++ g++ /usr/bin/g++-12 --slave /usr/bin/gcov gcov /usr/bin/gcov-12

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    test -f /usr/share/doc/kitware-archive-keyring/copyright || wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt-get update -q

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq cmake

RUN cmake_dir="$(find /usr/share -maxdepth 1 -maxdepth 1 -follow -name 'cmake-*.*' | sort -V | head -n 1 || true)" && \
    [ -n "${cmake_dir:-}" ] || { echo "ERROR: cmake directory not found in /usr/share" >&2; exit 1; } && \
    ln -sv "${cmake_dir}" /opt/build/cmake-dir && \
    /opt/build/fix-cmake-intel-openmp.sh /opt/build-cmake-dir

FROM builder-base AS builder-cuda

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    curl -fsSL -o cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(. /etc/os-release && echo $VERSION_ID | tr -d '.' | head -c4)/$(uname -p)/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring.deb && rm -f cuda-keyring.deb && \
    apt-get update -q
    
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends cuda-compiler-12-4 cuda-libraries-12-4 cuda-libraries-dev-12-4

RUN ( cd /usr/local; find . -maxdepth 1 -type d -name 'cuda-*' -printf '%f\n' | sort --version-sort | tail -n1 | xargs -I _ ln -sv _ cuda )

FROM builder-cuda AS builder-intel
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends intel-oneapi-compiler-dpcpp-cpp-and-cpp-classic && ( . "${ONEAPI_ROOT}/setvars.sh" && cd "${ONEAPI_ROOT}/compiler" && ln -sv "$(basename "${CMPLR_ROOT}")" classic )

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    apt-get install -yq --no-install-recommends \
        intel-oneapi-compiler-dpcpp-cpp \
        intel-oneapi-mkl-classic-devel \
        intel-oneapi-tbb-devel \
        intel-oneapi-tlt

RUN echo 'compiler=classic' > "${ONEAPI_ROOT}/classic.cfg"

FROM builder-intel AS builder

ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV CPATH="${DHCP_PREFIX}/include:${CPATH:-}"
ENV LIBRARY_PATH="${DHCP_PREFIX}/lib:${LIBRARY_PATH:-}"
ENV PKG_CONFIG_PATH="${DHCP_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH:-}"
ENV CMAKE_PREFIX_PATH="${DHCP_PREFIX}:${CMAKE_PREFIX_PATH:-}"
ENV CMAKE_INSTALL_PREFIX="${DHCP_PREFIX}"
ENV CMAKE_BUILD_TYPE="Release"
ENV CUDACXX=nvcc
ENV CUDAARCHS=75;86;89

RUN ldconfig

# Install Eigen 3.4:
WORKDIR /opt/build/eigen/src
ADD --link https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz src.tar.gz
SHELL ["/bin/bash", "-eE", "-o", "pipefail", "-c"]
RUN <<-EOF

    source "${ONEAPI_ROOT}/setvars.sh" --config="${ONEAPI_ROOT}/classic.cfg" && set -x
    export CC=icc CXX=icpc

    tar -xzf src.tar.gz --strip-components=1
    cd ../

    mkdir -p build && cd build
    cmake -Wno-dev \
            -D BUILD_TESTING:BOOL=OFF \
            -D BUILD_DOCUMENTATION:BOOL=OFF \
            -D BLA_VENDOR=Intel10_64lp \
        ../src || { tail -v -n +0 CMakeFiles/*.log || true; exit 1; }
    cmake --build .
    cmake --install .

EOF

# Install libs:
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

ENV SETVARS_ARGS="--include-intel-llvm"

WORKDIR /opt/build
COPY src/build-src/CMakeUserPresets.json /opt/build/CMakeUserPresets.json

FROM builder AS build-vtk-src
WORKDIR /opt/build/vtk
RUN git clone --branch release --depth=1 https://gitlab.kitware.com/vtk/vtk.git src && (cd src && git submodule update --init --remote --recommend-shallow ThirdParty/vtkm/vtkvtkm/vtk-m) && cp /opt/build/CMakeUserPresets.json src/

FROM build-vtk-src AS build-vtk
WORKDIR /opt/build/vtk/build
ENV NVCC_CCBIN=g++
ENV CUDAHOSTCXX="${NVCC_CCBIN}"
ARG NVCC_APPEND_FLAGS=-Xcompiler=-DEIGEN_USE_MKL_ALL -Xcompiler=-march=x86-64-v3 -Xcompiler=-O3
ENV NVCC_APPEND_FLAGS="${NVCC_APPEND_FLAGS}"
ARG USE_INTEL_OPTFLAGS=-DEIGEN_USE_MKL_ALL -qopt-zmm-usage=high -qmkl=parallel -O3 -xCORE-AVX2 -axSKYLAKE-AVX512
ENV __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS:-} ${USE_INTEL_OPTFLAGS}"
RUN source "${ONEAPI_ROOT}/setvars.sh" && \
	printenv && \
    cmake --preset intel-llvm \
            -D CMAKE_CXX_STANDARD=17 \
            -D BUILD_SHARED_LIBS:BOOL=ON \
            -D BUILD_TESTING:BOOL=OFF \
            -D VTK_ENABLE_REMOTE_MODULES:BOOL=OFF \
            -D VTK_ENABLE_WRAPPING:BOOL=ON \
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
            -D VTK_SMP_ENABLE_TBB:BOOL=ON \
            -D VTK_SMP_IMPLEMENTATION_TYPE:STRING=TBB \
            -D VTK_USE_CUDA:BOOL=ON \
            -D VTK_USE_X:BOOL=OFF \
            -D VTK_WRAP_PYTHON:BOOL=ON \
            -D VTK_WRAP_JAVA:BOOL=OFF \
            -D VTK_ENABLE_VTKM_OVERRIDES:BOOL=ON \
            -D VTKm_ENABLE_CUDA:BOOL=ON \
            -D VTKm_ENABLE_DEVELOPER_FLAGS:BOOL=OFF \
            -D VTKm_ENABLE_RENDERING:BOOL=OFF \
            -D VTKm_ENABLE_TESTING:BOOL=OFF \
            -D VTKm_ENABLE_TBB:BOOL=ON \
            -D VTKm_ENABLE_MPI:BOOL=OFF \
            ../src

ARG VTKM_NCPU=1
RUN . "${ONEAPI_ROOT}/setvars.sh" && \
	/usr/bin/time -v cmake --build . -t ThirdParty/vtkm/all -- -j ${VTKM_NCPU} || { tail -v -n 50 CMakeFiles/*.log 2>/dev/null || true; exit 1; }

RUN . "${ONEAPI_ROOT}/setvars.sh" && \
	/usr/bin/time -v cmake --build . -- -j ${NCPU:-$(nproc)} || { tail -v -n 50 CMakeFiles/*.log 2>/dev/null || true; exit 1; }

RUN cmake --install .

FROM build-vtk AS build-itk
WORKDIR /opt/build/itk
ADD --keep-git-dir=true https://github.com/InsightSoftwareConsortium/ITK.git#v5.4rc04 src
RUN sed -nE 's/icpc/icpx/g; s/icc/icx/g' src/CMake/ITKSetStandardCompilerFlags.cmake

RUN cp /opt/build/CMakeUserPresets.json src/
#RUN cd src/Modules/ThirdParty/VNL && rm -rf vxl && git clone --depth=1 https://github.com/vxl/vxl vxl

RUN echo "" > src/CMake/ITKSetStandardCompilerFlags.cmake
WORKDIR /opt/build/itk/build
RUN cp -v --no-clobber /opt/build/eigen/src/cmake/FindEigen3.cmake /opt/build/cmake-dir/Modules/
ARG __INTEL_PRE_CFLAGS=-fp-model=precise -diag-disable=10441 -diag-disable=15009 -diag-disable=10006 -diag-disable=10370 -diag-disable=10148 -diag-disable=10145 -wd10145 -qmkl -qtbb
ARG __INTEL_POST_CFLAGS=-xCORE-AVX2 -axSKYLAKE-AVX512 -std=c++17
ENV __INTEL_PRE_CFLAGS="${__INTEL_PRE_CFLAGS}"
ENV __INTEL_POST_CFLAGS="${__INTEL_POST_CFLAGS}"
RUN source "${ONEAPI_ROOT}/setvars.sh" && \
    cmake --preset intel-classic \
            -D CMAKE_CXX_STANDARD=17 \
            -D CMAKE_CXX_EXTENSIONS:BOOL=OFF \
            -D BUILD_DOCUMENTATION:BOOL=OFF \
            -D BUILD_EXAMPLES:BOOL=OFF \
            -D BUILD_SHARED_LIBS:BOOL=ON \
            -D BUILD_TESTING:BOOL=OFF \
            -D EIGEN_USE_MKL:BOOL=ON \
            -D EIGEN_USE_MKL_ALL:BOOL=ON \
            -D CMAKE_CXX_VISIBILITY_PRESET="default" \
            -D ITK_BUILD_DEFAULT_MODULES:BOOL=OFF \
            -D ITK_C_WARNING_FLAGS="-Wno-uninitialized -Wno-unused-parameter -wd1268 -wd981 -wd383 -wd1418 -wd1419 -wd2259 -wd1572 -wd424 -Wno-long-double -Wcast-align -Wdisabled-optimization -Wextra -Wformat=2 -Winvalid-pch -Wno-format-nonliteral -Wpointer-arith -Wshadow -Wunused -Wwrite-strings -Wno-strict-overflow" \
            -D ITK_CXX_WARNING_FLAGS="-wd1268 -wd981 -wd383 -wd1418 -wd1419 -wd2259 -wd1572 -wd424  -Wno-long-double -Wcast-align -Wdisabled-optimization -Wextra -Wformat=2 -Winvalid-pch -Wno-format-nonliteral -Wpointer-arith -Wshadow -Wunused -Wwrite-strings -Wno-strict-overflow -Wno-deprecated -Wno-invalid-offsetof -Wno-undefined-var-template -Woverloaded-virtual -Wctad-maybe-unsupported -Wstrict-null-sentinel" \
            -D CMAKE_BUILD_TYPE=Release \
            -D CMAKE_CXX_STANDARD=17 \
            -D BUILD_DOCUMENTATION:BOOL=OFF \
            -D BUILD_EXAMPLES:BOOL=OFF \
            -D BUILD_SHARED_LIBS:BOOL=ON \
            -D BUILD_TESTING:BOOL=OFF \
            -D CMAKE_CXX_VISIBILITY_PRESET="default" \
            -D ITK_USE_KWSTYLE=OFF \
            -D ITK_BUILD_DEFAULT_MODULES:BOOL=OFF \
            -D ITK_USE_MKL:BOOL=ON \
            -D ITK_USE_GPU:BOOL=ON \
            -D ITK_USE_SYSTEM_EIGEN:BOOL=ON \
            -D ITK_USE_SYSTEM_EXPAT:BOOL=ON \
            -D ITK_USE_SYSTEM_HDF5:BOOL=ON \
            -D ITK_USE_SYSTEM_JPEG:BOOL=ON \
            -D ITK_USE_SYSTEM_MINC:BOOL=OFF \
            -D ITK_USE_SYSTEM_PNG:BOOL=ON \
            -D ITK_USE_SYSTEM_TIFF:BOOL=ON \
            -D ITK_USE_TBB:BOOL=ON \
            -D ITK_USE_TBB_WITH_MKL:BOOL=ON \
            -D ITKGroup_Core:BOOL=ON \
            -D Module_ITKBiasCorrection:BOOL=ON \
            -D Module_ITKCommon:BOOL=ON \
            -D Module_ITKImageGrid:BOOL=ON \
            -D Module_ITKImageIntensity:BOOL=ON \
            -D Module_ITKImageStatistics:BOOL=ON \
            -D Module_ITKIOCSV:BOOL=ON \
            -D Module_ITKIOHDF5:BOOL=ON \
            -D Module_ITKIOImageBase:BOOL=ON \
            -D Module_ITKIOJPEG:BOOL=ON \
            -D Module_ITKIOMesh:BOOL=ON \
            -D Module_ITKIOMeshBase:BOOL=ON \
            -D Module_ITKIOMeshGifti:BOOL=ON \
            -D Module_ITKIOMeshOBJ:BOOL=ON \
            -D Module_ITKIOMeshOFF:BOOL=ON \
            -D Module_ITKIOMeshVTK:BOOL=ON \
            -D Module_ITKIOMeta:BOOL=ON \
            -D Module_ITKIOMINC:BOOL=ON \
            -D Module_ITKIONIFTI:BOOL=ON \
            -D Module_ITKIOPNG:BOOL=ON \
            -D Module_ITKIORAW:BOOL=ON \
            -D Module_ITKIOTIFF:BOOL=ON \
            -D Module_ITKIOTransformBase:BOOL=ON \
            -D Module_ITKTransformFactory:BOOL=ON \
            -D Module_ITKIOTransformHDF5:BOOL=ON \
            -D Module_ITKIOTransformInsightLegacy:BOOL=ON \
            -D Module_ITKIOVTK:BOOL=ON \
            -D Module_ITKIOXML:BOOL=ON \
            -D Module_ITKTestKernel:BOOL=OFF \
            -D Module_ITKThresholding:BOOL=ON \
            -D Module_ITKTransform:BOOL=ON \
        ../src

RUN . "${ONEAPI_ROOT}/setvars.sh" && \
    /usr/bin/time -v cmake --build . -- -j ${NCPU:-$(nproc)} || { tail -v -n 50 CMakeFiles/*.log 2>/dev/null || true; exit 1; }

RUN cmake --install .

FROM build-itk AS build-mirtk
ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR /opt/build/mirtk
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
ADD --link --keep-git-dir=true https://github.com/BioMedIA/MIRTK.git#973ce2fe3f9508dec68892dbf97cca39067aa3d6 src
COPY --link src/ext/antsCommandLineOption.h antsCommandLineOption.h
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
RUN <<-EOF

     #( cd src/Packages/Deformable && git checkout 9070e8e60e8721ed9675cdd6390de4e2f25ae2f3 )
     #( cd src/Packages/DrawEM; git checkout d2ff4e307638727d66aff3ece25496677bbd8df1; mv /opt/build/mirtk/antsCommandLineOption.h ThirdParty/ANTs/ )
     cp /opt/build/mirtk/antsCommandLineOption.h src/Packages/DrawEM/ThirdParty/ANTs/
     cp /opt/build/vtk/src/CMake/FindTBB.cmake /opt/dhcp/lib/cmake/vtk-9.2/vtkm/
     cp /opt/build/vtk/src/CMake/FindTBB.cmake src/CMake/Modules/

    source /opt/build/compilervars.sh
    export INTEL_OPTIMIZER_IPO="-qoverride-limits -no-inline-factor 800 -ipo"
    set_compiler_flags "" "-w2 -wd869 -wd593 -wd1286 -wd186 -wd612 -wd111 -wd654 -wd1125" "${INTEL_MKL_TBB_STATIC_FLAGS} -static-intel"
    export TBB_ROOT="${TBBROOT}"
    mkdir -p build && cd build
    
    cmake --debug-output -Wno-dev -GNinja \
            -D BUILD_DOCUMENTATION:BOOL=OFF \
            -D CMAKE_CXX_STANDARD=17 \
            -D CMAKE_CXX_EXTENSIONS=ON \
            -D BUILD_EXAMPLES:BOOL=OFF \
            -D BUILD_CHANGELOG:BOOL=OFF \
            -D BUILD_SHARED_LIBS:BOOL=ON \
            -D BUILD_TESTING:BOOL=ON \
            -D WITH_FLANN:BOOL=ON \
            -D WITH_MATLAB:BOOL=OFF \
            -D WITH_TBB:BOOL=ON \
            -D WITH_VTK:BOOL=ON \
            -D WITH_ITK:BOOL=ON \
            -D WITH_ZLIB:BOOL=ON \
            -D Eigen3_INCLUDE_DIR="${DHCP_PREFIX}/include/eigen3" \
            -D MODULE_Deformable:BOOL=ON \
            -D MODULE_DrawEM:BOOL=ON \
        ../src || { tail -v -n +0 CMakeFiles/*.log || true; exit 1; }
    cmake --build . -- -k 1 -l ${NCPU}
    cmake --install .
EOF

#     #git checkout be86b02d47a7ce74b17224891e25899c30f37d74 -- CMake/Modules/FindTBB.cmake Modules/Common/include/mirtk/Parallel.h Modules/Common/include/mirtk/Parallel.h Modules/Common/src/Parallel.cc
#     # sed -Ei 's/(^.*\bMIRTK_Common_EXPORT\b.*\btbb_scheduler.*$)/\/\/ \1/g' Modules/Common/include/mirtk/Parallel.h
#     # sed -Ei 's/(^.*tbb::task_scheduler_init.*$)/\/\/ \1/g' Modules/Common/include/mirtk/Parallel.h
#     # sed -Ei 's/(^.*tbb[/]task_scheduler_init.h.*$)/\/\/ \1/g' Modules/Common/include/mirtk/Parallel.h
#     #  git submodule foreach git fetch --all --tags
#     # fix_cmake_intel_openmp
#     # mkdir -p build && cd build
#     # export INTEL_OPTIMIZER_IPO="-ipo-separate"
#     # set_compiler_flags "" "${INTEL_MKL_TBB_STATIC_FLAGS} -static-intel"
#     # export TBB_ROOT="${TBBROOT}"
#     # export CMAKE_PREFIX_PATH="${TBBROOT}:${CMAKE_PREFIX_PATH:-}"
# EOF
#     cp /opt/build/vtk/src/CMake/FindTBB.cmake /opt/build/cmake-dir/Modules
#     rm /opt/dhcp/lib/cmake/vtk-9.2/FindTBB.cmake /opt/dhcp/lib/cmake/vtk-9.2/vtkm/FindTBB.cmake /opt/dhcp/lib/cmake/vtk-9.2/vtkm/cmake/FindTBB.cmake
#     cmake -Wno-dev -GNinja \
#             -D BUILD_DOCUMENTATION:BOOL=OFF \
#             -D BUILD_EXAMPLES:BOOL=OFF \
#             -D BUILD_CHANGELOG:BOOL=OFF \
#             -D BUILD_SHARED_LIBS:BOOL=ON \
#             -D BUILD_TESTING:BOOL=OFF \
#             -D USE_SYSTEM_EIGEN:BOOL=ON \
#             -D WITH_EIGEN3:BOOL=ON \
#             -D WITH_FLANN:BOOL=ON \
#             -D WITH_MATLAB:BOOL=OFF \
#             -D WITH_TBB:BOOL=ON \
#             -D WITH_VTK:BOOL=ON \
#             -D WITH_ITK:BOOL=ON \
#             -D DEPENDS_TBB_DIR="${TBBROOT}" \
#             -D DEPENDS_ITK_DIR="${DHCP_PREFIX}" \
#             -D DEPENDS_VTK_DIR="/opt/dhcp/lib/cmake/vtk-9.2" \
#             -D ITK_DIR="${DHCP_PREFIX}" \
#             -D VTK_DIR="${DHCP_PREFIX}" \
#             -D TBB_DIR="${TBBROOT}" \
#             -D DEPENDS_Eigen3_DIR="${DHCP_PREFIX}/include/eigen3" \
#             -D MODULE_Deformable:BOOL=ON \
#             -D MODULE_DrawEM:BOOL=ON \
#         ../src || { tail -v -n +0 CMakeFiles/*.log || true; exit 1; }
#     cmake --build .
#     cmake --install .
# EOF
FROM build-mirtk as built-mirtk-atlases
WORKDIR /opt/build/mirtk/src/Packages/DrawEM
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
RUN <<-EOF
    
    mkdir -p "${DRAWEMDIR}" && cp -Rv atlases "${DRAWEMDIR}"
    cp -R label_names "${DRAWEMDIR}"
    cp -R parameters "${DRAWEMDIR}"
    cp -R scripts "${DRAWEMDIR}"
    git config --worktree --unset-all core.worktree
    cp -R /opt/build/mirtk/src/.git/modules/Packages/DrawEM "${DRAWEMDIR}/.git"

EOF


FROM build-mirtk AS build-workbench
ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR /opt/build/workbench
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
ADD --link --keep-git-dir=true https://github.com/Washington-University/workbench.git#f0925edfd37db3808794a4df6355b18c80f49a04 src
COPY src/ext/NiftiHeader.cxx /opt/build/workbench/src/src/Nifti/NiftiHeader.cxx
COPY src/ext/FindQwt.cmake /opt/build/workbench/FindQwt.cmake
RUN <<-EOF

    sed --in-place -E 's/-openmp-link=static//g' src/src/CMakeLists.txt
    sed --in-place -E 's/DOT_USEFMA\s*0\s*[)]/DOT_USEFMA 1)/g' src/src/kloewe/dot/CMakeLists.txt
    sed --in-place -E 's/DOT_USEAVX512\s*0\s*[)]/DOT_USEAVX512 1)/g' src/src/kloewe/dot/CMakeLists.txt
    sed --in-place 's/if ((CMAKE_COMPILER_IS_GNUCC OR CLANG_FLAG) AND CMAKE_SIZEOF_VOID_P EQUAL 8)/if ((${CMAKE_CXX_COMPILER} MATCHES "^.*icpc$" OR CMAKE_COMPILER_IS_GNUCC OR CLANG_FLAG) AND CMAKE_SIZEOF_VOID_P EQUAL 8)/g' src/src/CMakeLists.txt
    sed --in-place -E '/^\s*ADD_SUBDIRECTORY\s*\(\s*(GuiQt|Qwt|Desktop|Qwt)\s*\)/d' src/src/CMakeLists.txt
    sed --in-place -E 's/PKG_CHECK_MODULES\(\s*Qwt\s+qwt\s*\)/FIND_PACKAGE(Qwt)/g' src/src/CMakeLists.txt
    sed --in-place -E '/^GuiQt\s*$/d' src/src/Tests/CMakeLists.txt
    sed --in-place -E '/^\$\{CMAKE_SOURCE_DIR\}\/GuiQt/d' src/src/Tests/CMakeLists.txt

    mkdir -p /opt/build/cmake-dir/Modules
    cp /usr/share/quazip/FindQuaZip5.cmake /opt/build/cmake-dir/Modules/FindQuaZip.cmake
    cp FindQwt.cmake /opt/build/cmake-dir/Modules/FindQwt.cmake

    (cd src/src/CZIlib/CZI && ln -sv eigen Eigen)

    mkdir -p build && cd build
    export INTEL_OPTIMIZER_IPO=''
    source "/opt/build/compilervars.sh"
    set_compiler_flags "-wd9 -I/opt/build/workbench/src/src/CZIlib/CZI" "-std=c++17 ${INTEL_MKL_OPENMP_DYNAMIC_FLAGS}"
    cmake -Wno-dev -GNinja \
            -D CMAKE_CXX_STANDARD=17 \
            -D CMAKE_CXX_EXTENSIONS=OFF \
            -D WORKBENCH_MESA_DIR=/usr \
            -D WORKBENCH_USE_QT5=TRUE \
            -D WORKBENCH_USE_SIMD=TRUE \
            -D WORKBENCH_USE_QT5_QOPENGL_WIDGET=TRUE \
            -D OpenGL_GL_PREFERENCE=GLVND \
        ../src/src
    cmake --build . -- -k 1 -l ${NCPU}
    ctest
    cmake --install .

EOF

FROM build-workbench AS build-sphericalmesh
ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR /opt/build/sphericalmesh
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
ADD --link --keep-git-dir=true https://github.com/amakropoulos/SphericalMesh.git#c41824cda791b806f79b88f2b27604a2f3268d19 src
COPY src/ext/SphericalMeshConvertToString.h /opt/build/sphericalmesh/src/include/mirtk/SphericalMeshConvertToString.h
RUN <<-EOF
    
    # Fix some issues with compilation:
    sed --in-place -E  's/std::to_string/convert_to_string/g' src/include/mirtk/*.h src/src/*.cc
    sed --in-place -E 's/(^#define M.*H_*[[:space:]]*$)/\1\n#include "mirtk\/SphericalMeshConvertToString.h"\n/g' src/include/mirtk/{M2SParameters.h,M2SDiffuser.h,M2SRemesher.h,MeshToSphere.h}

    mkdir -p build && cd build
    source "/opt/build/compilervars.sh"
    set_compiler_flags "" "-std=c++17 ${INTEL_MKL_TBB_STATIC_FLAGS}"
    cmake -Wno-dev -GNinja \
            -D CMAKE_CXX_STANDARD=17 \
        ../src
    cmake --build .
    cmake --install .
    install -vpDm755 bin/* "${DHCP_PREFIX}/bin"
EOF


# Install FSL:
FROM build-sphericalmesh AS build-fsl

SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
RUN \
    <<-EOF

    # Set up micromamba and install FSL:
    export CI=1
    micromamba install --dry-run --yes --verbose -n base --channel intel --channel https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public --channel conda-forge fsl-avwutils==2209.0 fsl-flirt==2111.0 fsl-bet2==2111.0
    exit 1
    micromamba clean --yes --all

EOF

FROM build-fsl  AS build-pipeline-applications
ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR "/opt/build/pipeline-applications"
COPY src/applications /opt/build/pipeline-applications/src
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
RUN <<-EOF

    mkdir -p build && cd build
    source "/opt/build/compilervars.sh"
    set_compiler_flags "" "-std=c++17 ${INTEL_MKL_TBB_STATIC_FLAGS}"

    cmake -Wno-dev -GNinja \
            -D CMAKE_CXX_STANDARD=17 \
        ../src
    cmake --build . -- -k 1 -l ${NCPU}
    cmake --install .
    install -v -Dm755 bin/* ${DHCP_PREFIX}/bin
EOF

FROM build-pipeline-applications AS build-pipeline
ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR "${DHCP_DIR}"
COPY --chmod=a+rX src/dhcp-pipeline "${DHCP_DIR}"
COPY version ${DHCP_DIR}/version

SHELL ["/bin/bash", "-eEx", "-c"]
RUN <<-EOF

    ln -sv "${DRAWEMDIR}/atlases" ${DHCP_DIR}/atlases
    echo "${DHCP_PREFIX}/lib/mirtk" >> /etc/ld.so.conf.d/0-dhcp-pipeline.conf
    (source "/opt/build/compilervars.sh"; find "${DHCP_PREFIX}" -type f -executable 2>/dev/null | xargs ldd 2>/dev/null | grep "=>[[:space:]]*${ONEAPI_ROOT}" | grep -o -E '/\S*' | sort | uniq | xargs -I {} cp -v {} "${DHCP_PREFIX}/lib/")
    ldconfig
EOF


FROM base AS final
ARG MAMBA_DOCKERFILE_ACTIVATE=1
ENV ITK_GLOBAL_DEFAULT_THREADER=tbb
ENV DHCP_DIR="${DHCP_PREFIX}/src"
ENV DRAWEMDIR="${DHCP_PREFIX}/share/DrawEM"
ENV FSLDIR="${CONDA_PREFIX}"
ENV ENV_NAME="${FSLDIR}"
WORKDIR /
COPY --from=build-pipeline "${DHCP_PREFIX}" "${DHCP_PREFIX}"
COPY --chmod=755 --from=build-pipeline /opt/build/mirtk/build/lib/mirtk/tools/N4  "${DHCP_PREFIX}/lib/mirtk/tools/N4"
# Install tools:
SHELL ["/bin/bash", "-eEx", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked --mount=type=cache,sharing=locked,target=/var/lib/apt/lists \
    <<-EOF

    if ! command -v dc >/dev/nul 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-cache info dc >/dev/null 2>&1 || apt-get update -qq 
        apt-get install -yq --no-install-recommends dc
    fi
    ldconfig
    ( cd "$DRAWEMDIR" && git init && git config user.email 'nobody@example.com'; git config  user.name 'nobody'; git commit --allow-empty --allow-empty-message --no-verify -m ''; )
    echo 'set -eE' >> "${DHCP_DIR}/parameters/configuration.sh"
EOF

WORKDIR /data
ENTRYPOINT ["/opt/dhcp/src/dhcp-pipeline.sh"]
CMD ["-help"]
