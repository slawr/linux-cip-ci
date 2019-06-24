#/bin/bash
# Copyright (C) 2019, Renesas Electronics Europe GmbH, Chris Paterson
# <chris.paterson2@renesas.com>
#
# This script scans the OUTPUT_DIR for any built Kernels and creates/submits the
# relevant test jobs to the CIP LAVA master.
#
# Script specific dependencies:
# lavacli aws
#
# The following must be set in GitLab CI variables for lavacli to work:
# $CIP_LAVA_LAB_USER
# $CIP_LAVA_LAB_TOKEN
#
# The following must be set in GitLab CI variables for aws to work:
# $CIP_CI_AWS_ID
# $CIP_CI_AWS_KEY
#
# Parameters:
# None
#
################################################################################

set -ex

################################################################################
WORK_DIR="$CI_BUILDS_DIR/$CI_PROJECT_PATH"
TMP_DIR="$WORK_DIR/tmp"
OUTPUT_DIR="$WORK_DIR/output"
TEMPLATE_DIR="/opt/healthcheck_templates"
################################################################################
AWS_URL_UP="s3://download.cip-project.org/ciptesting/ci"
AWS_URL_DOWN="https://s3-us-west-2.amazonaws.com/download.cip-project.org/ciptesting/ci"
LAVACLI_ARGS="--uri https://$CIP_LAVA_LAB_USER:$CIP_LAVA_LAB_TOKEN@lava.ciplatform.org/RPC2"
################################################################################

set_up () {
	mkdir -p $TMP_DIR
}

clean_up () {
	rm -rf $TMP_DIR
}

# Using job definition templates based on device tree names
get_template () {
	local machine=$(echo "$DTB" | rev | cut -f 2- -d '.' | rev)
	TEMPLATE="$machine.yaml"
}

create_job () {
	echo "Create job"

	get_template

	DTB_URL="$AWS_URL_DOWN/$CONFIG_DIR/dtb/$DTB"
	KERNEL_URL="$AWS_URL_DOWN/$CONFIG_DIR/kernel/$KERNEL"
	MODULES_URL="$AWS_URL_DOWN/$CONFIG_DIR/modules/$MODULES"

	JOB_NAME="${VERSION}_${ARCH}_${CONFIG}_${DTB}"
	JOB_DEFINITION="$TMP_DIR/$JOB_NAME.yaml"
	cp $TEMPLATE_DIR/$TEMPLATE $JOB_DEFINITION

	sed -i "s|JOB_NAME|$JOB_NAME|g" $JOB_DEFINITION
	if [ ! -z "$MODULES" ]; then
		sed -i "/DTB_URL/ a \    modules:\n      url: $MODULES_URL\n      compression: gz" $JOB_DEFINITION
	fi
	sed -i "s|DTB_URL|$DTB_URL|g" $JOB_DEFINITION
	sed -i "s|KERNEL_URL|$KERNEL_URL|g" $JOB_DEFINITION
}

configure_aws () {
	aws configure set aws_access_key_id $CIP_CI_AWS_ID
	aws configure set aws_secret_access_key $CIP_CI_AWS_KEY
	aws configure set default.region us-west-2
	aws configure set default.output text
}

upload_binaries () {

	configure_aws

	aws s3 sync $OUTPUT_DIR/. $AWS_URL_UP --acl public-read
}

print_kernel_info () {
	set +x

	echo "Kernel Found"
	echo "----------"
	echo "Version: $VERSION"
	echo "Arch: $ARCH"
	echo "Config: $CONFIG"
	echo "Kernel: $KERNEL"
	echo "DTB: $DTB"
	echo "Modules: $MODULES"
	echo "----------"

	set -x
}

find_kernels () {
	# Example build output directory structure
	# $OUTPUT_DIR/
	# └── 4.4.154-cip28_5dcb70a7e56e
	#     ├── arm
	#     │   └── shmobile_defconfig
	#     │       ├── dtb
	#     │       │   └── r8a7743-iwg20d-q7-dbcm-ca.dtb
	#     │       └── kernel
	#     │           └── uImage
	#     └── arm64
	#         └── defconfig
	#             ├── dtb
	#             │   └── r8a774c0-ek874.dtb
	#             ├── kernel
	#             │   └── Image
	#             └── modules
	#                 └── modules.tar.gz

	if [ ! -d $OUTPUT_DIR ]; then
		echo "No output directory found, probably because there were no successful builds."
		clean_up
		exit 0
	fi

	cd $OUTPUT_DIR

	for VERSION_DIR in `find * -maxdepth 0 -type d`
	do
		VERSION=`echo "$VERSION_DIR" | sed "s/.*\///"`

		for ARCH_DIR in `find $VERSION_DIR/* -maxdepth 0 -type d`
		do
			ARCH=`echo "$ARCH_DIR" | sed "s/.*\///"`

			for CONFIG_DIR in `find $ARCH_DIR/* -maxdepth 0 -type d`
			do
				CONFIG=`echo "$CONFIG_DIR" | sed "s/.*\///"`
				KERNEL=`find $CONFIG_DIR/kernel/ -type f | sed "s/.*\///"`
				DTB=`find $CONFIG_DIR/dtb/ -type f | sed "s/.*\///"`
				MODULES=`find $CONFIG_DIR/modules/ -type f | sed "s/.*\///"`

				print_kernel_info
				create_job
			done
		done
	done
}

submit_job() {
	# TODO: Add yaml validation

        # Make sure job file exists
	if [ -f $1 ]; then
		echo "Submitting $1 to LAVA master..."
		# Catch error that occurs if invalid yaml file is submitted
		ret=`lavacli $LAVACLI_ARGS jobs submit $1` || ERROR=1

		if [[ $ret != [0-9]* ]]
		then
			echo "Something went wrong with job submission. LAVA returned:"
			echo ${ret}
		else
			echo "Job submitted successfully as #${ret}."
		fi
	fi
}


submit_jobs () {
	for JOB in $TMP_DIR/*.yaml
	do
		submit_job $JOB
	done
}


trap clean_up SIGHUP SIGINT SIGTERM
set_up

find_kernels
upload_binaries
submit_jobs

# TODO: Check to see if submitted jobs were actually successful.

clean_up

