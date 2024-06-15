Not really used anymore. Keeping for reference.

example docker compose:


```yaml
secrets:
  host_ssh_key:
    file: /var/services/homes/collin/.ssh/id_rsa

services:
    ubuntu-cli:
      container_name: ubuntu-cli
      restart: unless-stopped
      build:
        context: ubuntu
      secrets:
        - host_ssh_key
      extra_hosts:
        - "host.docker.internal:host-gateway" # enables host.docker.internal as a dns name
```

