FROM caddy:2.10.0-builder AS builder
RUN xcaddy build v2.10.0 \
    --with github.com/tailscale/caddy-tailscale \
    --with github.com/caddy-dns/hetzner

FROM caddy:2.10.0
RUN apk add curl
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile
COPY html /srv
