# Atuin K8s deployment management

# Create all secrets for atuin deployment
create-secrets:
    #!/usr/bin/env bash
    set -euo pipefail

    kubectl create namespace atuin --dry-run=client -o yaml \
        | kubectl apply -f -
    kubectl create secret generic atuin-postgres-secrets \
        --from-literal=POSTGRES_PASSWORD="${ATUIN_POSTGRES_PASSWORD}" \
        --namespace=atuin \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic atuin-secrets \
        --from-literal=ATUIN_DB_URI="postgresql://atuin:${ATUIN_POSTGRES_PASSWORD}@postgres:5432/atuin" \
        --namespace=atuin \
        --dry-run=client -o yaml | kubectl apply -f -

# List secrets in atuin namespace
list-secrets:
    kubectl get secrets -n atuin

# Deploy atuin to k8s
apply:
    kubectl apply -k overlays/production

# Delete atuin deployment (keeps namespace and secrets)
delete:
    kubectl delete -k overlays/production --ignore-not-found=true

# Get atuin pod status
status:
    kubectl get pods -n atuin

# View atuin server logs
logs:
    kubectl logs -n atuin -l app=atuin -f

# View postgres logs
logs-postgres:
    kubectl logs -n atuin -l app=postgres -f

# Connect to atuin postgres database
psql:
    kubectl exec -it -n atuin postgres-0 -- psql -U atuin atuin

# Restart atuin deployment
restart:
    kubectl rollout restart deployment/atuin -n atuin

# Get all atuin resources
get-all:
    kubectl get all,ingress,pvc -n atuin

# Describe atuin deployment
describe:
    kubectl describe deployment/atuin -n atuin

# Describe postgres statefulset
describe-postgres:
    kubectl describe statefulset/postgres -n atuin

# Export postgres data to backup file
backup file="atuin_backup.sql":
    kubectl exec -n atuin postgres-0 -- pg_dump -U atuin atuin > {{file}}

# Import postgres data from backup file
restore file="atuin_backup.sql":
    kubectl exec -i -n atuin postgres-0 -- psql -U atuin atuin < {{file}}

# Full deployment: create secrets and apply manifests
deploy: create-secrets apply

# Clean up everything including namespace (WARNING: deletes all data)
clean:
    kubectl delete namespace atuin --ignore-not-found=true
