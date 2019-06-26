# linux-cip-ci
This project builds the containers and scripts used in the CI testing of the
linux-cip Kernel.

There are two docker containers, "build-image" and "test-image". You can guess
what they are for.

## build-image
Docker container that includes Linux Kernel build dependencies and a full clone
of the
[linux-cip](https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git/)
git repository.

Also included is the `build_kernel.sh` script which handles the actual building
of the Kernel for the given architecture and configurations.

### build_kernel.sh
This script starts by installing the relevant gcc compiler for the given
architecture. It then builds the Kernel, device trees and modules as required
for the given configuration.

The GitLab CI configuration then archives the relevant binaries ready for the
test stage to pick up.

**Parameters**  
$1 - Architecture to build (arm, arm64)  
$2 - Kernel configuration to build (must be in-tree)

## test-image
Used to build a container that includes the dependencies required for testing.

Also included is the `submit_tests.sh` script which creates and submits LAVA
test jobs.

### submit_tests.sh
This script starts by searching for Kernels that are in the `$OUTPUT_DIR`
directory. Each Kernel then gets uploaded to an S3 bucket on AWS. The script
then creates LAVA test jobs as required and submits them to the CIP LAVA master.

**Prerequisites**  
The `submit_tests.sh` script relies on the following secret environment
variables being set. This can be done in GitLab in `settings/ci_cd`.
* CIP_CI_AWS_ID
* CIP_CI_AWS_KEY
* CIP_LAVA_LAB_USER
* CIP_LAVA_LAB_TOKEN

## Example Use
The below `.gitlab-ci.yml` file shows how linux-cip-ci can be used.

Note that the notify stage at the bottom will need `LINUX_CIP_BUILD_TRIGGER` to
be set in the linux-cip-ci GitLab CI/CD settings to match the trigger configured
in the linux-cip GitLab CI/CD settings.

```
variables:
  GIT_STRATEGY: none
  DOCKER_DRIVER: overlay2

before_script:
  - cd /opt/linux
  - git fetch origin
  - git checkout $CI_COMMIT_SHA

build_arm_shmobile_defconfig:
  stage: build
  image: registry.gitlab.com/cip-playground/linux-cip-ci:build-latest
  script:
    - /opt/build_kernel.sh arm shmobile_defconfig
  artifacts:
    name: "$CI_JOB_NAME"
    when: on_success
    paths:
      - output

build_arm64_defconfig:
  stage: build
  image: registry.gitlab.com/cip-playground/linux-cip-ci:build-latest
  script:
    - /opt/build_kernel.sh arm64 defconfig
  artifacts:
    name: "$CI_JOB_NAME"
    when: on_success
    paths:
      - output

run_tests:
  stage: test
  image: registry.gitlab.com/cip-playground/linux-cip-ci:test-latest
  when: always
  before_script: []
  script:
    - /opt/submit_tests.sh

notify:
  stage: notify
  image: appropriate/curl
  before_script: []
  script:
    - "curl -X POST -F token=$LINUX_CIP_BUILD_TRIGGER -F ref=linux-4.19.y-cip https://gitlab.com/api/v4/projects/2678032/trigger/pipeline"
  retry: 1
  only:
    - master
```

