#/bin/bash
# Copyright (C) 2019, Renesas Electronics Europe GmbH, Chris Paterson
# <chris.paterson2@renesas.com>
#
# This script scans the OUTPUT_DIR for any built Kernels and creates/submits the
# relevant test jobs to the CIP LAVA master.
#
# Script specific dependencies:
# lavacli aws pwd
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
WORK_DIR=`pwd`
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
	local machine=$(echo "$DTB_NAME" | rev | cut -f 2- -d '.' | rev)
	TEMPLATE="$machine.yaml"
}

create_job () {
	get_template

	local dtb_url="$AWS_URL_DOWN/$DTB"
	local kernel_url="$AWS_URL_DOWN/$KERNEL"
	local modules_url="$AWS_URL_DOWN/$MODULES"

	local job_name="${VERSION}_${ARCH}_${CONFIG}_${DTB_NAME}"
	local job_definition="$TMP_DIR/$job_name.yaml"
	cp $TEMPLATE_DIR/$TEMPLATE $job_definition

	sed -i "s|JOB_NAME|$job_name|g" $job_definition
	if [ ! -z "$MODULES" ]; then
		sed -i "/DTB_URL/ a \    modules:\n      url: $modules_url\n      compression: gz" $job_definition
	fi
	sed -i "s|DTB_URL|$dtb_url|g" $job_definition
	sed -i "s|KERNEL_URL|$kernel_url|g" $job_definition
}

configure_aws () {
	aws configure set aws_access_key_id $CIP_CI_AWS_ID
	aws configure set aws_secret_access_key $CIP_CI_AWS_KEY
	aws configure set default.region us-west-2
	aws configure set default.output text
}

upload_binaries () {
	configure_aws
	aws s3 sync $OUTPUT_DIR/. $AWS_URL_UP --exclude jobs --acl public-read
}

print_kernel_info () {
	set +x

	echo "Job Found"
	echo "----------"
	echo "Version: $VERSION"
	echo "Arch: $ARCH"
	echo "Config: $CONFIG"
	echo "Kernel: $KERNEL_NAME"
	echo "DTB: $DTB_NAME"
	echo "Modules: $MODULES_NAME"
	echo "----------"

	set -x
}

# JOBS_FILE should be structured with space separated values as below, one job
# per line:
# VERSION ARCH CONFIG KERNEL DEVICE_TREE MODULES
# MODULES is optional
find_jobs () {
	# Search for job files
	for jobfile in $OUTPUT_DIR/*.jobs; do
		while read version arch config kernel device_tree modules; do
			VERSION=$version
			ARCH=$arch
			CONFIG=$config
			KERNEL=$kernel
			DTB=$device_tree
			MODULES=$modules
	
			# Get filename from path
			KERNEL_NAME=`echo "$KERNEL" | sed "s/.*\///"`
			DTB_NAME=`echo "$DTB" | sed "s/.*\///"`
			MODULES_NAME=`echo "$MODULES" | sed "s/.*\///"`

			print_kernel_info
			create_job
		done < $jobfile
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
	for JOB in $TMP_DIR/*.yaml; do
		submit_job $JOB
	done
}


trap clean_up SIGHUP SIGINT SIGTERM
set_up

find_jobs
upload_binaries
submit_jobs

# TODO: Check to see if submitted jobs were actually successful.

clean_up
