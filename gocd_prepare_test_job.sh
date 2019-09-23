#/bin/bash
#
# Copyright (C) 2019 GENIVI Alliance
# Gunnar Andersson, <gandersson@genivi.org>
#
# The following must be set in CI environment variables for lavacli to work:
# $CIP_LAVA_LAB_USER
# $CIP_LAVA_LAB_TOKEN
# If values are not set, they are read from a credentials file, which
# must then exist.
#
################################################################################
WORK_DIR=`pwd`
OUTPUT_DIR="$WORK_DIR/output"

# Default LAVA_CREDENTIALS_FILE locations
# (Not used if CIP_LAVA_LAB_USER/TOKEN is defined in env)
if [ -z "$LAVA_CREDENTIALS_FILE" ] ; then
  if [ -f "$WORK_DIR/cip_lava_lab_cred" ] ; then
    LAVA_CREDENTIALS_FILE="$WORK_DIR/cip_lava_lab_cred"
  fi
  if [ -f "$HOME/cip_lava_lab_cred" ] ; then
    LAVA_CREDENTIALS_FILE="$HOME/cip_lava_lab_cred"
  fi
fi


#FIXME  VARS ARE NOT USED BY SUBMIT SHELL SCRIPT

warn() {
  cat <<EOT 1>&2
  $@
EOT
}

get_credentials() {
  if [ -z "$CIP_LAVA_LAB_USER" ] ; then
    if [ -z "$LAVA_CREDENTIALS_FILE" ] ; then
      echo "Please specify CIP_LAVA_LAB_USER/TOKEN or LAVA_CREDENTIALS_FILE"
      exit 2
    fi

    if [ ! -f "$LAVA_CREDENTIALS_FILE" ] ; then
      echo "Specified credentials file ($LAVA_CREDENTIALS_FILE) is missing!  Lava interaction will not be possible"
      echo "Stopping..."
      exit 1
    else
      . "$LAVA_CREDENTIALS_FILE"
    fi
  fi

  if [ -z "$CIP_LAVA_LAB_USER" ] ; then
    echo "Bug: CIP_LAVA_LAB_USER is still not specified.  Lava interaction will not be possible"
    echo "Stopping..."
    exit 3
  fi
}

################################################################################

# Just some helpers that will fail gracefully if an environment
# variable is undefined, which it might be sometimes
deref() { eval echo \$$1 ; }
get_value() {
  local concept=$1
  local value=$(deref $2)  # variable name passed in $2
  if [ -z "$value" ] ; then
     warn "Warning, value for variable $2 was not defined -- using default value"
     value="unknown_${concept}"
  fi
  echo "$value"
}

get_version() {
  get_value label GO_PIPELINE_LABEL
}
get_pipeline_instance() {
  echo "$(get_value pipe_name GO_PIPELINE_NAME)/$(get_value counter GO_PIPELINE_COUNTER)"
}
get_arch() {
  get_value arch MACHINE  # $MACHINE value from Yocto build
}
get_config() {
  echo "FIXME_UNKNOWN_CONFIG"
}
get_device() {
  # Coding the relationship between $TARGET used in our Yocto builds
  # and the expected test target device type:
  if [ "$TARGET" = "r-car-m3-starter-kit" ] ; then
    echo "r8a7743-iwg20m"
  else
    # For now we don't know any other targets...
    echo "UNSUPPORTED_MACHINE"
  fi
}
get_kernel() {
  echo "DEFAULT_KERNEL"  # Not defined  -> basically it is fixed in test definition template
}
get_device_tree() {
  echo "DEFAULT_DTB"     # Not defined, same as above
}
get_modules() {
  echo "DEFAULT_MODULES"     # Not defined, same as above
}
get_jobname() {
  echo "myjob.jobs"
}

jobfile="$OUTPUT_DIR/$(get_jobname)"
cat <<EOT >$jobfile
# This is a comment
# Format (BUILD_ID added by us)
# VERSION BUILD_ID ARCH CONFIG DEVICE KERNEL DEVICE_TREE MODULES
$(get_version) $(get_pipeline_instance) $(get_arch) $(get_config) $(get_device) $(get_kernel) $(get_device_tree) $(get_modules)
EOT

get_credentials
