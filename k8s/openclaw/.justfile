# OpenClaw (dopeclaw) K8s deployment management

# Create secrets for openclaw deployment
# Requires OPENROUTER_API_KEY, SLACK_BOT_TOKEN, SLACK_APP_TOKEN environment variables
create-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${OPENROUTER_API_KEY:-}" ]; then
        echo "Error: OPENROUTER_API_KEY environment variable is required"
        exit 1
    fi
    if [ -z "${SLACK_BOT_TOKEN:-}" ]; then
        echo "Error: SLACK_BOT_TOKEN environment variable is required"
        exit 1
    fi
    if [ -z "${SLACK_APP_TOKEN:-}" ]; then
        echo "Error: SLACK_APP_TOKEN environment variable is required"
        exit 1
    fi
    kubectl create namespace openclaw --dry-run=client -o yaml \
        | kubectl apply -f -
    kubectl create secret generic openclaw-secrets \
        --namespace openclaw \
        --from-literal=OPENROUTER_API_KEY="${OPENROUTER_API_KEY}" \
        --from-literal=SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN}" \
        --from-literal=SLACK_APP_TOKEN="${SLACK_APP_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created openclaw-secrets secret"

# Deploy openclaw
deploy:
    kubectl apply -k base/

# Delete openclaw deployment (keeps namespace and secrets)
delete:
    kubectl delete -k base/ --ignore-not-found=true

# Get openclaw pod status
status:
    kubectl get pods,svc,pvc -n openclaw

# View openclaw logs
logs:
    kubectl logs -n openclaw -l app=openclaw -f

# Restart openclaw deployment
restart:
    kubectl rollout restart deployment/openclaw -n openclaw

# Get all openclaw resources
get-all:
    kubectl get all,pvc,servicemonitor -n openclaw

# Describe openclaw deployment
describe:
    kubectl describe deployment/openclaw -n openclaw

# Update the system prompt and restart (for personality tweaking)
update-prompt:
    kubectl create configmap openclaw-system-prompt \
        --from-file=system-prompt.txt=base/system-prompt.txt \
        --namespace openclaw \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl rollout restart deployment/openclaw -n openclaw

# List secrets in openclaw namespace
list-secrets:
    kubectl get secrets -n openclaw

# Full deployment: create secrets and apply manifests
full-deploy: create-secrets deploy
