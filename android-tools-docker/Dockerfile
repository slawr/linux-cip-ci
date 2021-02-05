FROM ubuntu:16.04
RUN apt-get update ; apt-get install -y curl unzip usbutils
RUN curl -L https://dl.google.com/android/repository/platform-tools-latest-linux.zip >/tmp/pft.zip
RUN unzip /tmp/pft.zip && rm /tmp/pft.zip
ENV PATH /bin:/usr/bin:/platform-tools
CMD /bin/sh

