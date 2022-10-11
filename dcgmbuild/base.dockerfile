FROM ubuntu:20.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN set -ex; \
    apt-get update; \
    apt-get full-upgrade -yq

RUN set -ex; \
    apt-get install -qy \
    autoconf \
    automake \
    bison \
    build-essential \
    curl \
    file \
    flex \
    gawk \
    git \
    gperf \
    help2man \
    libexpat1-dev \
    libncurses5-dev \
    libtool \
    libtool-bin \
    subversion \
    texinfo \
    unzip \
    wget \
    python \
    python-dev

WORKDIR /root
COPY checksums /root/
RUN set -ex; mkdir -p crosstool-ng; \
    wget https://github.com/crosstool-ng/crosstool-ng/archive/61c4ccac5c751a7e9900d32af53e9f01e6c09bd8.tar.gz -O crosstool-ng.tar.gz; \
    sha512sum -c checksums; \
    tar xf crosstool-ng.tar.gz -C crosstool-ng --strip-components=1; \
    cd crosstool-ng; \
    ./bootstrap; \
    ./configure --prefix=/opt/crosstool-ng; \
    make -j12; \
    make install; \
    cd /root; \
    rm -rf /root/*

RUN useradd -m builder
RUN mkdir -p /opt/cross && chmod -R a+rw /opt/cross && chown builder:builder /opt/cross
USER builder
WORKDIR /home/builder
RUN mkdir -p src

ENV PATH="/opt/crosstool-ng/bin:${PATH}"
# no patches at this moment
# COPY patches /home/builder/patches/

COPY --chown=builder:builder x86_64.config /home/builder/x86_64/.config
WORKDIR /home/builder/x86_64
RUN CT_PREFIX=/opt/cross ct-ng build -j12
RUN rm /opt/cross/build.log* || true

COPY --chown=builder:builder ppc64le.config /home/builder/ppc64le/.config
WORKDIR /home/builder/ppc64le
RUN CT_PREFIX=/opt/cross ct-ng build -j12
RUN rm /opt/cross/build.log* || true

COPY --chown=builder:builder aarch64.config /home/builder/aarch64/.config
WORKDIR /home/builder/aarch64
RUN CT_PREFIX=/opt/cross ct-ng build -j12
RUN rm /opt/cross/build.log* || true

################
## Actual image
################
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

RUN set -ex; apt-get update -q && apt-get full-upgrade -qy
RUN set -ex; apt-get update -q && apt-get install -qy curl wget vim make bzip2 automake autoconf gettext graphviz \
    libedit-dev libtool xz-utils patch python3 python3-dev python3-pip pylint3 \
    build-essential xz-utils pkg-config graphviz software-properties-common \
    flex bison rpm unzip cpio ninja-build

RUN add-apt-repository ppa:git-core/ppa
RUN apt-get update -q && apt-get install -qy git

COPY --from=builder --chown=root:root /opt/cross/* /opt/cross/
ENV PATH="/opt/cross/bin:/opt/cross/x86_64-linux-gnu:/usr/local/go/bin:${PATH}"
RUN set -ex; \
    echo /opt/cross/lib >> /etc/ld.so.conf.d/cross_tools.conf; \
    echo /opt/cross/lib64 >> /etc/ld.so.conf.d/cross_tools.conf
