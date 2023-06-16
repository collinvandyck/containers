FROM ubuntu:latest

RUN apt-get update && apt-get install -y xterm x11-apps
RUN useradd -ms /bin/bash xterm
USER xterm
WORKDIR /home/xterm
