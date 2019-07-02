FROM ubuntu:18.04
MAINTAINER Chris Paterson <chris.paterson2@renesas.com>

ENV DEBIAN_FRONTEND noninteractive

# Install dependencies
RUN apt-get update
RUN apt-get install -y apt-utils git build-essential libncurses-dev bison flex libssl-dev libelf-dev bc u-boot-tools wget kmod

COPY build_kernel.sh /opt/
RUN chmod +x /opt/build_kernel.sh

