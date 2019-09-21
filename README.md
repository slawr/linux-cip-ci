# Scripts for submitting jobs to LAVA test farm

This primarily reuses submit_tests.sh and the associated lava templates
setup from the **[linux-cip-ci project](https://gitlab.com/cip-project/cip-testing/linux-cip-ci/)**

While there are quite some changes, it seems useful to keep the git history
and relationship to the project so I decided to start with forking **linux-cip-ci**.

Removed:
--------

I [removed](https://github.com/gunnarx/linux-cip-ci/commit/611d5ef154794c4ea704319ff02c082e6fc45976) anything we don't use just for clarity, but the
shared git history allows these to be easily brought back when needed:

`build.Dockerfile`
`build_kernel.sh ` -- We don't need to build kernels (see below for details)

`test.Dockerfile`  -- Our CI workers (go-agent) that run this are already docker containers. That environment works well so no real need to keep another  container definition for testing/repeatability

`.gitlab-ci.yml` -- We don't use GitLab's CI function

Added:
------
`gocd_prepare_test_job.sh` -- This script outputs the ".jobs" definition into
the output directory in the format that submit_tests.sh expects

Changed:
--------

No kernels are compiled since we use this only to send complete images, and
these are built already when we get to this point.  This means that the
metadata values for CONFIG, DTB, MODULES and KERNEL are less useful for us.
The configuration of those are defined in the particular image build and
the values are usually left empty.

The original project uses AWS S3 for artifact sharing between the CI system
and Lava.  In our case we SFTP/SSHFS combination and removed all AWS
interaction.

This version adds one more configurable option in the .jobs definition named
`PIPELINE_ID` because we would like to identify jobs by which pipeline is being
tested. In the Go.CD CI system, the combination of pipeline name and counter
is the official way to identify a particular build. (We also use a shorter
build-label that identifies repo fork, branch, and commit hash which is 
set as the `VERSION` metadata)

For the benefit of the final job name, `CONFIG` is also "misused" to specify
pipeline identity (since as explained above, varying kernel-config is not the
purpose here, and it can still be found, if needed, by tracing back to
the image build identification)

`CIP_LAVA_LAB_USER` and `CIP_LAVA_LAB_TOKEN` login credentials are as
documented in the original but this version adds the alternative to specify
the path to a sourceable script defining these variables.  The path to such
a script shall then be defined in: `LAVA_CREDENTIALS_FILE`

`TEST_TIMEOUT` and `SUBMIT_ONLY` are as documented in the original.

Modified version by Gunnar Andersson <gandersson @@ genivi.org>

For additional/original documentation please refer to the [original README](https://gitlab.com/cip-project/cip-testing/linux-cip-ci/blob/master/README.md)
