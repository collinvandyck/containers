caddyconfig:
	vps dc exec caddy curl -Ss localhost:2019/config/

caddypush:
	#!/usr/bin/env bash
	cat caddy/vps/Caddyfile	| vps dc exec -T caddy curl \
		-Ss -H 'Content-Type: text/caddyfile' \
		--data-binary @- \
		localhost:2019/load

caddyfmt:
	caddy fmt caddy/vps/Caddyfile --overwrite

caddylogs:
	vps dc exec caddy tail -n 1000 -F /var/log/caddy/caddy.log
