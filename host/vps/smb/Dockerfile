FROM alpine:3.14
RUN apk --no-cache upgrade && apk --no-cache add samba samba-common-tools supervisor bash iptables
RUN mkdir /config /shared
COPY *.conf /config/
COPY docker-entrypoint.sh /
VOLUME /config /shared

# exposes samba's default ports (135 for End Point Mapper [DCE/RPC Locator Service],
# 137, 138 for nmbd and 139, 445 for smbd)
EXPOSE 135/tcp 137/udp 138/udp 139/tcp 445/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]
