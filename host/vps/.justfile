caddyconfig:
	dc exec caddy curl -Ss localhost:2019/config/

caddypush:
	#!/usr/bin/env bash
	cat caddy/Caddyfile	| vps dc exec -T caddy curl \
		-Ss -H 'Content-Type: text/caddyfile' \
		--data-binary @- \
		localhost:2019/load

caddyfmt:
	caddy fmt caddy/Caddyfile --overwrite

caddylogs:
	dc exec caddy tail -n 1000 -F /var/log/caddy/caddy.log

caddyaccess:
	dc exec caddy cat /var/log/caddy/caddy.log | jq -r '.request.host | select (.!=null)' | sort | uniq -c | sort -nr
