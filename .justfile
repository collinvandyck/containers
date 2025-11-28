# Containers repo - shared k8s utilities

chart := "k8s/charts/webapp"

# --- Helm webapp deployments ---

# Preview rendered manifests for a helm app
# Usage: just helm-template freshrss
[group('helm')]
helm-template app:
    helm template {{app}} {{chart}} -f k8s/{{app}}/values.yaml -n {{app}}

# Deploy/upgrade a helm app
# Usage: just helm-deploy freshrss
[group('helm')]
helm-deploy app:
    helm upgrade --install {{app}} {{chart}} -f k8s/{{app}}/values.yaml -n {{app}} --create-namespace

# Uninstall a helm app (keeps namespace and PVCs)
# Usage: just helm-uninstall freshrss
[group('helm')]
helm-uninstall app:
    helm uninstall {{app}} -n {{app}}

# Show status of a helm release
# Usage: just helm-status freshrss
[group('helm')]
helm-status app:
    helm status {{app}} -n {{app}}

# List all helm releases
[group('helm')]
helm-list:
    helm list -A

# Follow logs for a helm app
# Usage: just helm-logs freshrss
[group('helm')]
helm-logs app:
    kubectl logs -n {{app}} -l app={{app}} -f

# Restart a helm app deployment (pulls latest image if using :latest)
# Usage: just helm-restart freshrss
[group('helm')]
helm-restart app:
    kubectl rollout restart deployment/{{app}} -n {{app}}

# Get all resources for a helm app
# Usage: just helm-get freshrss
[group('helm')]
helm-get app:
    kubectl get all,ingress,pvc -n {{app}}

# --- Utilities ---

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
