FROM ubuntu:latest

ENV TZ="America/New_York"
ENV LANG=C.UTF-8

RUN apt update && apt-get install -y tzdata
RUN apt update && \
	apt-get install -y \
		build-essential \
		ca-certificates \
		curl \
		gettext \
		git \
		man \
		man-db \
		sudo \
		zsh
	
ARG user=collin

# user setup
RUN useradd $user --create-home 
RUN echo "$user:$user" | chpasswd && adduser $user sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# fix man pages
RUN cp /bin/man.REAL /bin/man
RUN cp /bin/man.REAL /usr/bin/man

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=$user
USER $user
WORKDIR /home/$user

RUN touch .zshenv

COPY bootstrap /usr/local/bin/
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

