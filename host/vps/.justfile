deploy-caddy:
    dc -f containers.yml build caddy
    dc -f containers.yml up -d caddy

copy-resume:
    cp ../../../resume/5xx.engineer.html caddy/html/resume/
    cp ../../../resume/5xx.engineer.pdf caddy/html/resume/
    cp ../../../resume/style.css caddy/html/resume/

deploy-resume:
    dc -f containers.yml build caddy
    dc -f containers.yml up -d caddy

deploy-blog:
    dc -f blog.yml pull
    dc -f blog.yml up -d --force-recreate blog

caddyconfig:
	dc exec caddy curl -Ss localhost:2019/config/

push:
	scripts/caddypush

caddypush: caddyfmt
	dc cp caddy/Caddyfile caddy:/tmp/Caddyfile
	dc exec -T caddy curl \
			-Ss -H 'Content-Type:text/caddyfile' \
			--data-binary @/tmp/Caddyfile \
			localhost:2019/load

caddyfmt:
	caddy fmt caddy/Caddyfile --overwrite

caddylogs:
	dc -f containers.yml exec caddy tail -n 1000 -F /var/log/caddy/caddy.log |tspin

caddyaccess:
	dc exec caddy cat /var/log/caddy/caddy.log | jq -r '.request.host | select (.!=null)' | sort | uniq -c | sort -nr

debug:
	echo $DOCKER_HOST

