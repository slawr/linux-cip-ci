FROM ubuntu:18.04
MAINTAINER Chris Paterson <chris.paterson2@renesas.com>

ENV DEBIAN_FRONTEND noninteractive

# Install dependencies
RUN apt-get update
RUN apt-get install -y apt-utils lavacli python3-pip

# Install AWS CLI
RUN pip3 install awscli

# Copy test script
COPY submit_tests.sh /opt/
RUN chmod +x /opt/submit_tests.sh

# Copy healthcheck templates
COPY healthcheck_templates /opt/healthcheck_templates 


