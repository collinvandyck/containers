https://grafana.com/docs/loki/latest/send-data/docker-driver/

# Upgrading

    docker plugin disable loki --force
    docker plugin upgrade loki grafana/loki-docker-driver:2.9.2 --grant-all-permissions
    docker plugin enable loki
    systemctl restart docker

# disable

    docker plugin disable loki --force
    docker plugin rm loki
