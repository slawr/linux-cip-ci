FROM ubuntu:18.04
MAINTAINER Chris Paterson <chris.paterson2@renesas.com>

ENV DEBIAN_FRONTEND noninteractive

# Install dependencies
RUN apt-get update \
&& apt-get install -y --no-install-recommends apt-utils lavacli python3-pip \
&& rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN pip3 install awscli

# Copy healthcheck templates
COPY healthcheck_templates /opt/healthcheck_templates

# Copy test script
COPY submit_tests.sh /opt/
RUN chmod +x /opt/submit_tests.sh
