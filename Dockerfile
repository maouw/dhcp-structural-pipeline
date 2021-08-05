## Build Docker image for execution of dhcp pipelines within a Docker
## container with all modules and applications available in the image

FROM ubuntu:xenial
MAINTAINER John Cupitt <jcupitt@gmail.com>
LABEL Description="dHCP structural-pipeline" Vendor="BioMedIA"

# Git repository and commit SHA from which this Docker image was built
# (see https://microbadger.com/#/labels)
ARG VCS_REF
LABEL org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/biomedia/dhcp-structural-pipeline"

# No. of threads to use for build (--build-arg THREADS=8)
# By default, all available CPUs are used. 
ARG THREADS

# install prerequsites
# - build tools
# - FSL 5.0.11 bet needs "dc"
# - FSL latest
#
#	  * -E is not suported on ubuntu (rhel only), so we make a quick n dirty
#	    /etc/fsl/fsl.sh 
#
#	  * fslinstaller.py fails in post_install as it gives the wrong flag 
#	    to wget to enable silent mode ... run the post install again 
#	    to fix this
#
# MIRTK master is python3 only

RUN apt-get update 
RUN apt-get install -y \
  bc \
  g++-5 \
  git \
  libboost-dev \
  libexpat1-dev \
	libgstreamer1.0-dev \
  libqt4-dev dc \
	libssl-dev \
	libtbb-dev \
  libxt-dev \
  python3 \
  unzip \
	wget \
  zlib1g-dev 

WORKDIR /usr/local/src

# xenial comes with 3.5, too old for MIRTK master
ENV CMAKE_VERSION 3.18.2
ENV CMAKE_URL https://github.com/Kitware/CMake/releases/download

RUN wget ${CMAKE_URL}/v$CMAKE_VERSION/cmake-$CMAKE_VERSION.tar.gz \
	&& tar xf cmake-${CMAKE_VERSION}.tar.gz \
	&& cd cmake-${CMAKE_VERSION} \
	&& ./configure \
	&& make V=0 \
	&& make install

COPY fslinstaller.py /usr/local/src
RUN echo "please ignore the 'failed to download miniconda' error coming soon" \
	&& python fslinstaller.py -V 5.0.11 -q -d /usr/local/fsl \
	&& export FSLDIR=/usr/local/fsl \
	&& echo "retrying miniconda install ..." \
	&& /usr/local/fsl/etc/fslconf/post_install.sh \
	&& mkdir -p /etc/fsl \
	&& echo "FSLDIR=/usr/local/fsl; . \${FSLDIR}/etc/fslconf/fsl.sh; PATH=\${FSLDIR}/bin:\${PATH}; export FSLDIR PATH" > /etc/fsl/fsl.sh 

# more stuff needed by chunks of the struct pipeline when we update to latest
# itk/vtk/mirtk
RUN apt-get install -y \
  libhdf5-dev 

COPY . structural-pipeline
RUN NUM_CPUS=${THREADS:-`cat /proc/cpuinfo | grep processor | wc -l`} \
	&& echo "Maximum number of build threads = $NUM_CPUS" \
	&& cd structural-pipeline \
	&& ./setup.sh -j $NUM_CPUS

WORKDIR /data
ENTRYPOINT ["/usr/local/src/structural-pipeline/dhcp-pipeline.sh"]
CMD ["-help"]

