#!/usr/bin/env bash

set -euo pipefail

install() {
	apt-get install -y curl
	curl -fsSL https://tailscale.com/install.sh | sh
}

apt-get update && \
	install && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

