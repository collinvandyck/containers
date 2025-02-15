openwebui:
    #!/usr/bin/env bash
    export COMPOSE_FILE=ai.yml
    dc pull openwebui
    dc up -d --force-recreate openwebui
    dc logs -f openwebui

langflow:
    #!/usr/bin/env bash
    set -eu
    cp -r "$BOBIVERSE"/* langflow/data/bobiverse
    dc -f ai.yml up -d --build langflow

deploy-atuin:
    dc -f containers.yml pull atuin
    dc -f containers.yml up -d atuin

caddy-mark-stable:
    #!/usr/bin/env bash
    stable="$(docker inspect caddy --format '{{{{.Image}}')"
    echo docker tag ${stable} containers-caddy:stable

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

