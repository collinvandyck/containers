FROM caddy:2.8.4-alpine

COPY Caddyfile /etc/caddy/Caddyfile
COPY boundaq /srv/boundaq
COPY resume /srv/resume
COPY dotfiles /srv/dotfiles

EXPOSE 8080

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
