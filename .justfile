# Containers repo - shared k8s utilities

# Create ghcr-secret in a namespace for pulling images from ghcr.io
# Usage: just create-ghcr-secret <namespace>
# Requires GHCR_PAT environment variable
create-ghcr-secret namespace:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${GHCR_PAT:-}" ]; then
        echo "Error: GHCR_PAT environment variable is required"
        exit 1
    fi
    kubectl create namespace {{namespace}} --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret docker-registry ghcr-secret \
        --docker-server=ghcr.io \
        --docker-username=collinvandyck \
        --docker-password="${GHCR_PAT}" \
        --docker-email=collinvandyck@gmail.com \
        --namespace={{namespace}} \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created ghcr-secret in namespace {{namespace}}"
