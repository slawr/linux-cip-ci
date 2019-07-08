FROM ubuntu:18.04
MAINTAINER Chris Paterson <chris.paterson2@renesas.com>

ENV DEBIAN_FRONTEND noninteractive

# Install dependencies
RUN apt-get update \
&& apt-get install -y --no-install-recommends apt-utils git build-essential \
libncurses-dev bison flex libssl-dev libelf-dev bc u-boot-tools wget kmod \
ca-certificates \
&& rm -rf /var/lib/apt/lists/*

# Clone cip-kernel-config repository
RUN git clone https://gitlab.com/cip-project/cip-kernel/cip-kernel-config.git \
/opt/cip-kernel-config

# Copy build script
COPY build_kernel.sh /opt/
RUN chmod +x /opt/build_kernel.sh
