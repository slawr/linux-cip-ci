#/bin/bash
# Copyright (C) 2019, Renesas Electronics Europe GmbH, Chris Paterson
# <chris.paterson2@renesas.com>
#
# This script scans the OUTPUT_DIR for any built Kernels and creates/submits the
# relevant test jobs to the CIP LAVA master.
#
# Script specific dependencies:
# lavacli aws pwd sed date
#
# The following must be set in GitLab CI variables for lavacli to work:
# $CIP_LAVA_LAB_USER
# $CIP_LAVA_LAB_TOKEN
#
# The following must be set in GitLab CI variables for aws to work:
# $CIP_CI_AWS_ID
# $CIP_CI_AWS_KEY
#
# Other global variables
# $TEST_TIMEOUT: Length of time in minutes to wait for test completion. If
#                unset a default of 30 minutes is used.
# $SUBMIT_ONLY: Set to 'true' if you don't want to wait to see if submitted LAVA
#               jobs complete. If this is not set a default of 'false' is used.
#
################################################################################

set -e

################################################################################
WORK_DIR=`pwd`
OUTPUT_DIR="$WORK_DIR/output"
TEMPLATE_DIR="/opt/lava_templates"
################################################################################
AWS_URL_UP="s3://download.cip-project.org/ciptesting/ci"
AWS_URL_DOWN="https://s3-us-west-2.amazonaws.com/download.cip-project.org/ciptesting/ci"
LAVACLI_ARGS="--uri https://$CIP_LAVA_LAB_USER:$CIP_LAVA_LAB_TOKEN@lava.ciplatform.org/RPC2"
if [ -z "$TEST_TIMEOUT" ]; then TEST_TIMEOUT=30; fi
if [ -z "$SUBMIT_ONLY" ]; then SUBMIT_ONLY=false; fi
################################################################################

set_up () {
	TMP_DIR="$(mktemp -d)"
}

clean_up () {
	rm -rf $TMP_DIR
}

get_template () {
	TEMPLATE="$TEMPLATE_DIR/$DEVICE.yaml"
}

create_job () {
	get_template

	local dtb_url="$AWS_URL_DOWN/$DTB"
	local kernel_url="$AWS_URL_DOWN/$KERNEL"
	local modules_url="$AWS_URL_DOWN/$MODULES"

	INDEX="0"
	if $USE_DTB; then
		local job_name="${VERSION}_${ARCH}_${CONFIG}_${DTB_NAME}"
	else
		local job_name="${VERSION}_${ARCH}_${CONFIG}"
	fi

	local job_definition="$TMP_DIR/${INDEX}_${job_name}.yaml"
	INDEX=$((INDEX+1))

	cp $TEMPLATE $job_definition

	sed -i "s|JOB_NAME|$job_name|g" $job_definition
	if [ ! -z "$MODULES" ]; then
		sed -i "/DTB_URL/ a \    modules:\n      url: $modules_url\n      compression: gz" $job_definition
	fi
	if $USE_DTB; then
		sed -i "s|DTB_URL|$dtb_url|g" $job_definition
	fi
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

	# Note: If there are multiple jobs in the same pipeline building the
	# same SHA, same ARCH and same CONFIG _name_, AWS binaries will be
	# overwritten.
	aws s3 sync $OUTPUT_DIR/. $AWS_URL_UP --exclude jobs --acl public-read
}

print_kernel_info () {
	echo "Job Found"
	echo "----------"
	echo "Version: $VERSION"
	echo "Arch: $ARCH"
	echo "Config: $CONFIG"
	echo "Device: $DEVICE"
	echo "Kernel: $KERNEL_NAME"
	echo "DTB: $DTB_NAME"
	echo "Modules: $MODULES_NAME"
	echo "----------"
}

# JOBS_FILE should be structured with space separated values as below, one job
# per line:
# VERSION ARCH CONFIG KERNEL DEVICE_TREE MODULES
# MODULES is optional
find_jobs () {
	# Make sure there is at least one job file
	if [ `find $OUTPUT_DIR -maxdepth 1 -name "*.jobs" -printf '.' |  wc -c` -eq 0 ]; then
		echo "No jobs found"
		clean_up
		# Quit cleanly as technically there is nothing wrong, it's just
		# that either no builds were successful or none that wanted
		# testing.
		exit 0
	fi

	# Process job files
	for jobfile in $OUTPUT_DIR/*.jobs; do
		while read version arch config device kernel device_tree modules; do
			VERSION=$version
			ARCH=$arch
			CONFIG=$config
			DEVICE=$device
			KERNEL=$kernel
			DTB=$device_tree
			MODULES=$modules

			if [ $DTB == "N/A" ]; then
				USE_DTB=false
			else
				USE_DTB=true
			fi

			# Get filename from path
			KERNEL_NAME=`echo "$KERNEL" | sed "s/.*\///"`
			MODULES_NAME=`echo "$MODULES" | sed "s/.*\///"`
			if $USE_DTB; then
				DTB_NAME=`echo "$DTB" | sed "s/.*\///"`
			fi

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
		local ret=`lavacli $LAVACLI_ARGS jobs submit $1` || error=true

		if [[ $ret != [0-9]* ]]
		then
			echo "Something went wrong with job submission. LAVA returned:"
			echo ${ret}
		else
			echo "Job submitted successfully as #${ret}."
			STATUS[${ret}]="Submitted"
			JOBS+=(${ret})
		fi
	fi
}


submit_jobs () {
	for JOB in $TMP_DIR/*.yaml; do
		submit_job $JOB
	done
}

check_if_all_finished() {
        for i in "${JOBS[@]}"
        do
                if [ ${STATUS[$i]} != "Finished" ]; then
                        return 1
                fi
        done
        return 0
}

print_current_status () {
	echo "------------------------------"
	echo "Current job status:"
	for i in "${JOBS[@]}"; do
		echo "Job #$i: ${STATUS[$i]}"
	done
}

check_status () {
	# Current time + timeout time
	local end_time=`date +%s -d "+ $TEST_TIMEOUT min"`
	local error=false

	if [ ${#JOBS[@]} -ne 0 ]
	then
		print_current_status

		while true
		do
			# Get latest status
			for i in "${JOBS[@]}"
			do
				if [ ${STATUS[$i]} != "Finished" ]
				then
					local ret=`lavacli $LAVACLI_ARGS \
						jobs show $i \
						| grep state \
						| cut -d ":" -f 2 \
						| awk '{$1=$1};1'`


					if [ ${STATUS[$i]} != $ret ]; then
						STATUS[$i]=$ret

						# Something has changed
						print_current_status
					else
						STATUS[$i]=$ret
					fi
				fi
			done

			if check_if_all_finished; then
				break
			fi

			# Check timeout
			local now=$(date +%s)
			if [ $now -ge $end_time ]; then
				echo "Timed out waiting for test jobs to complete"
				error=true
				break
			fi

			# Small wait to avoid spamming the server too hard
			sleep 10
		done

		if check_if_all_finished; then
			# Print job outcome
			for i in "${JOBS[@]}"
			do
				local ret=`lavacli $LAVACLI_ARGS \
					jobs show $i \
					| grep Health \
					| cut -d ":" -f 2 \
					| awk '{$1=$1};1'`
				echo "Job #$i completed. Job health: $ret"

				if [ ${ret} != "Complete" ]; then
					error=true
				fi
			done
		fi
	fi

	if $error; then
		echo "Errors during testing"
		clean_up
		exit 1
	fi

	echo "All testing completed"
}


trap clean_up SIGHUP SIGINT SIGTERM
set_up

find_jobs
upload_binaries
submit_jobs
if ! $SUBMIT_ONLY; then
	check_status
fi

clean_up
