FROM caddy:2.9.1-builder AS builder
RUN xcaddy build v2.9.1 \
    --with github.com/tailscale/caddy-tailscale \
    --with github.com/caddy-dns/hetzner

FROM caddy:2.9.1
RUN apk add curl
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile
COPY html /srv
