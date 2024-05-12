FROM ubuntu:24.04

COPY ./install.sh /
ENV DEBIAN_FRONTEND=noninteractive
RUN /install.sh
ENV DEBIAN_FRONTEND=

CMD ["bash", "-c", "sleep 356d"]
