FROM caddy:2.8.4-builder AS builder
RUN xcaddy build v2.8.4 \
    --with github.com/tailscale/caddy-tailscale \
    --with github.com/caddy-dns/hetzner

FROM caddy:2.8.4
RUN apk add curl
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile
COPY html /srv
