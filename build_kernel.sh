#/bin/bash
#
# Copyright (C) 2019, Renesas Electronics Europe GmbH, Chris Paterson
# <chris.paterson2@renesas.com>
#
# This script takes a given architecture and configuration and installs the
# required compiler and builds the Kernel with it, ready for testing.
#
# Compiler installation influenced from the work done by Hiramatsu-san at:
# https://github.com/mhiramat/linux-cross
#
# Script specific dependencies:
# wget uname nproc make tar
#
# Parameters:
# $1 - Architecture to build
# $2 - Kernel configuration to build
#
################################################################################

set -ex

################################################################################
WORK_DIR="$CI_BUILDS_DIR/$CI_PROJECT_PATH"
GCC_VER="8.1.0"
COMPILER_BASE_URL="https://cdn.kernel.org/pub/tools/crosstool/files/bin"
COMPILER_INSTALL_DIR="$WORK_DIR/gcc/"
TMP_DIR="$WORK_DIR/tmp"
MODULE_INSTALL_DIR="$TMP_DIR/modules"
OUTPUT_DIR="$WORK_DIR/output"
################################################################################
CPUS=`nproc`
HOST_ARCH=`uname -m`
################################################################################

set_up () {
	mkdir -p $TMP_DIR
	mkdir -p $COMPILER_INSTALL_DIR
	mkdir -p $MODULE_INSTALL_DIR
	mkdir -p $OUTPUT_DIR
}

clean_up () {
	rm -rf $TMP_DIR
	rm -rf $MODULE_INSTALL_DIR
}

clean_build () {
	make mrproper
}

# Parameters:
# $1 - Kernel configuration to build
configure_kernel () {
	# TODO: Add cip-kernel-configs support

	case "$1" in
		"shmobile_defconfig")
			# This config prefers uImage
			BUILD_FLAGS="$BUILD_FLAGS LOADADDR=0x40008000"
			IMAGE_TYPE="uImage"
			CONFIG=$1
			;;
		"")
			CONFIG="defconfig"
			;;
		*)
			CONFIG=$1
			;;
	esac

	make $BUILD_FLAGS $CONFIG

	get_kernel_name
}

get_kernel_name () {
	# Work out Kernel version
	local sha=`git log --pretty=format:"%h" -1`
	local version=`make kernelversion`

	# Check for local version
	# WARNING: This will only work if there is one file named localversion*
	local localversionfile=`find . -maxdepth 1 -name localversion*`
	if [ ! -z $localversionfile ]; then
		local localversion=`cat $localversionfile`
		version=$version$localversion
	fi
	version=${version}_${sha}

	# Define Kernel image name
	KERNEL_NAME=$IMAGE_TYPE_$CONFIG_$version
}

build_kernel () {
	make $BUILD_FLAGS $IMAGE_TYPE

	if grep -qc "CONFIG_MODULES=y" .config; then
		build_modules
	fi
}

build_dtbs () {
	make $BUILD_FLAGS dtbs
}

build_modules () {
	make $BUILD_FLAGS modules
	make $BUILD_FLAGS modules_install INSTALL_MOD_PATH=$MODULE_INSTALL_DIR

	tar -C ${MODULE_INSTALL_DIR} -czf $TMP_DIR/modules.tar.gz lib
}

# TODO: Make sure docker image installs the compilers as well
install_compiler () {
	local ext=".tar.gz"
	local url="https://cdn.kernel.org/pub/tools/crosstool/files/bin"
	local gcc_file="$HOST_ARCH-gcc-$GCC_VER-nolibc-$GCC_NAME$ext"
	
	wget -q -P $TMP_DIR/ $url/$HOST_ARCH/$GCC_VER/$gcc_file
	if [ $? -ne 0 ]; then
		echo "Error: Compiler download failure"
		clean_up
		exit 1
	fi		
	
	tar xf $TMP_DIR/$gcc_file -C $COMPILER_INSTALL_DIR
}

configure_compiler () {
	local compiler_exec=($COMPILER_INSTALL_DIR/gcc-*/${GCC_NAME}/bin/${GCC_NAME}-gcc)
	[[ -x $compiler_exec ]] || install_compiler

	BUILD_FLAGS="-j$CPUS ARCH=$BUILD_ARCH CROSS_COMPILE=${compiler_exec%gcc}"
}

# Parameters
# $1 - Target arch
configure_arch () {

	case "$1" in
		"arm")
			BUILD_ARCH="arm"
			GCC_NAME="arm-linux-gnueabi"
			IMAGE_TYPE="zImage"
			;;
		"arm64")
			BUILD_ARCH="arm64"
			GCC_NAME="aarch64-linux"
			IMAGE_TYPE="Image"
			;;
		"")
			echo "Error: No target architecture provided"
			clean_up
			exit 1
			;;
		*)
			echo "Error: Target architecture not supported"
			clean_up
			exit 1
			;;
	esac
}

# Parameters
# $1 - Target arch
# $2 - Kernel configuration to build
configure_build () {
	configure_arch $1 
	configure_compiler
	configure_kernel $2
}

copy_output () {
	local output_dir=$OUTPUT_DIR/$KERNEL_NAME/$BUILD_ARCH/$CONFIG/
	mkdir -p $output_dir/kernel
	mkdir -p $output_dir/dtb
	mkdir -p $output_dir/modules

	# Kernel
	cp arch/$BUILD_ARCH/boot/$IMAGE_TYPE $output_dir/kernel

	# Only copy DTBs we care about
	# submit_tests.sh is based on there only being 1 device tree
	case $BUILD_ARCH in
		"arm")
			case $CONFIG in
				"shmobile_defconfig")
					cp arch/arm/boot/dts/r8a7743-iwg20d-q7-dbcm-ca.dtb $output_dir/dtb
					;;
			esac
			;;
		"arm64")
			case $CONFIG in
				"defconfig")
					cp arch/arm64/boot/dts/renesas/r8a774c0-ek874.dtb $output_dir/dtb
					;;
			esac
			;;
	esac

	# Modules
	if [ -f "$TMP_DIR/modules.tar.gz" ]; then
		cp $TMP_DIR/modules.tar.gz $output_dir
		rm -rf $TMP_DIR/modules.tar.gz
		rm -rf $MODULE_INSTALL_DIR
	fi
}


trap clean_up SIGHUP SIGINT SIGTERM
set_up

# TODO: Add support for multiple Kernel configs (it's quicker to build them in
# the same job, rather than build from scratch each time).
################################################################################
# Run the below for each configuration you want to build
configure_build $1 $2
build_kernel
build_dtbs
copy_output
################################################################################

clean_up

