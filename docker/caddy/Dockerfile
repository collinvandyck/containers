FROM caddy:2.8.4-builder AS builder
RUN xcaddy build v2.8.4 \
    --with github.com/tailscale/caddy-tailscale
RUN ls -l /usr/bin/caddy


FROM caddy:2.8.4
RUN apk add curl
RUN ls -l /usr/bin/caddy
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN ls -l /usr/bin/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile

