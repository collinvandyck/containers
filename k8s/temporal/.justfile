# Temporal K8s deployment management

# Create the temporal namespace
create-namespace:
    kubectl create namespace temporal --dry-run=client -o yaml | kubectl apply -f -

# Create postgres credentials secret
# Requires TEMPORAL_POSTGRES_PASSWORD environment variable
create-postgres-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${TEMPORAL_POSTGRES_PASSWORD:-}" ]; then
        echo "Error: TEMPORAL_POSTGRES_PASSWORD environment variable is required"
        exit 1
    fi
    kubectl create secret generic temporal-postgres-secrets \
        --namespace temporal \
        --from-literal=POSTGRES_PASSWORD="${TEMPORAL_POSTGRES_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created temporal-postgres-secrets secret"

# Create all secrets needed so far
create-secrets: create-namespace create-postgres-secret
    @echo "Secrets created"

# List secrets in temporal namespace
list-secrets:
    kubectl get secrets -n temporal

# Apply postgres manifests
apply-postgres:
    kubectl apply -f postgres/

# Deploy postgres (secrets + manifests)
deploy-postgres: create-secrets apply-postgres
    @echo "Postgres deployed"

# Get pod status in the temporal namespace
status:
    kubectl get pods -n temporal

# View postgres logs
logs-postgres:
    kubectl logs -n temporal -l app=postgres -f

# Connect to temporal postgres database
psql:
    kubectl exec -it -n temporal postgres-0 -- psql -U temporal temporal

# Describe postgres statefulset
describe-postgres:
    kubectl describe statefulset/postgres -n temporal

# Get all temporal resources
get-all:
    kubectl get all,ingress,pvc,certificate -n temporal

# ============================================================================
# Certificates
# ============================================================================

# Apply CA + frontend server certificate manifests
apply-certs:
    kubectl apply -f certs/selfsigned-issuer.yaml
    kubectl apply -f certs/temporal-ca.yaml
    kubectl apply -f certs/frontend-cert.yaml

# Show certificate status in the temporal namespace
cert-status:
    kubectl get certificate,issuer -n temporal

# Issue a client cert for a worker/CLI identity and export to ~/.temporal/<name>/
# Usage: just gen-client-cert worker-foo
gen-client-cert NAME:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{NAME}}"
    out="${HOME}/.temporal/${name}"
    mkdir -p "${out}"
    kubectl apply -f - <<EOF
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: client-${name}
      namespace: temporal
    spec:
      secretName: client-${name}-tls
      duration: 8760h
      renewBefore: 720h
      commonName: ${name}
      subject:
        organizations:
          - temporal-clients
      usages:
        - client auth
        - digital signature
        - key encipherment
      privateKey:
        algorithm: ECDSA
        size: 256
      issuerRef:
        name: temporal-ca
        kind: Issuer
    EOF
    echo "Waiting for certificate to be issued..."
    kubectl wait --for=condition=Ready -n temporal "certificate/client-${name}" --timeout=60s
    kubectl get secret -n temporal "client-${name}-tls" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${out}/tls.crt"
    kubectl get secret -n temporal "client-${name}-tls" -o jsonpath='{.data.tls\.key}' | base64 -d > "${out}/tls.key"
    kubectl get secret -n temporal "client-${name}-tls" -o jsonpath='{.data.ca\.crt}' | base64 -d > "${out}/ca.crt"
    chmod 600 "${out}/tls.key"
    echo "Wrote ${out}/{tls.crt,tls.key,ca.crt}"

# List client certificates
list-client-certs:
    kubectl get certificate -n temporal -l '!cert-manager.io/certificate-name' \
        || kubectl get certificate -n temporal | grep '^client-'

# Delete a client certificate and its secret
# Note: this prevents future use of the key but does not invalidate sessions
# already established with the cert. There is no CRL/OCSP in this setup.
delete-client-cert NAME:
    kubectl delete certificate -n temporal "client-{{NAME}}" --ignore-not-found=true
    kubectl delete secret -n temporal "client-{{NAME}}-tls" --ignore-not-found=true

# Apply the in-cluster UI client certificate
apply-ui-client-cert:
    kubectl apply -f certs/ui-client-cert.yaml

# ============================================================================
# Temporal server (helm)
# ============================================================================

# Add the temporalio helm repo
add-helm-repo:
    helm repo add temporalio https://go.temporal.io/helm-charts || true
    helm repo update

# Render manifests without applying
helm-template:
    helm template temporal temporalio/temporal \
        --namespace temporal \
        --values temporal-values.yaml

# Install or upgrade the temporal helm release
helm-install:
    helm upgrade --install temporal temporalio/temporal \
        --namespace temporal \
        --values temporal-values.yaml \
        --wait \
        --timeout 10m

# Uninstall the temporal helm release (keeps namespace, postgres data, secrets)
helm-uninstall:
    helm uninstall temporal --namespace temporal

# Show helm release status
helm-status:
    helm status temporal --namespace temporal

# Tail logs from all temporal server components
logs-server:
    kubectl logs -n temporal -l app.kubernetes.io/name=temporal --tail=200 -f

# Open a shell in the admintools pod
admintools:
    kubectl exec -it -n temporal deploy/temporal-admintools -- bash

# ============================================================================
# Web UI ingress (oauth2-proxy + traefik)
# ============================================================================

# Create OAuth2 proxy credentials secret
# Requires TEMPORAL_OAUTH_CLIENT_ID, TEMPORAL_OAUTH_CLIENT_SECRET,
# and TEMPORAL_OAUTH_COOKIE_SECRET (32 url-safe base64 chars; gen with
# `openssl rand -base64 32 | tr -- '+/' '-_' | tr -d '='`)
create-oauth-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${TEMPORAL_OAUTH_CLIENT_ID:?required}"
    : "${TEMPORAL_OAUTH_CLIENT_SECRET:?required}"
    : "${TEMPORAL_OAUTH_COOKIE_SECRET:?required}"
    kubectl create secret generic oauth2-proxy-secrets \
        --namespace temporal \
        --from-literal=client-id="${TEMPORAL_OAUTH_CLIENT_ID}" \
        --from-literal=client-secret="${TEMPORAL_OAUTH_CLIENT_SECRET}" \
        --from-literal=cookie-secret="${TEMPORAL_OAUTH_COOKIE_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created oauth2-proxy-secrets secret"

# Apply UI ingress + oauth2-proxy resources
apply-ui:
    kubectl apply -f ui/

# Restart oauth2-proxy
restart-oauth:
    kubectl rollout restart deployment/oauth2-proxy -n temporal

# Tail oauth2-proxy logs
logs-oauth:
    kubectl logs -n temporal -l app=oauth2-proxy -f

# ============================================================================
# Frontend gRPC ingress (TCP passthrough)
# ============================================================================

# Apply the IngressRouteTCP for temporal.5xx.engineer:443 -> frontend:7233
apply-frontend-ingress:
    kubectl apply -f frontend-ingress.yaml

# Smoke-test the public frontend with a local cert
# Usage: just check-frontend worker-foo
check-frontend NAME:
    #!/usr/bin/env bash
    set -euo pipefail
    name="{{NAME}}"
    out="${HOME}/.temporal/${name}"
    test -f "${out}/tls.crt" || { echo "missing ${out}/tls.crt — run gen-client-cert first"; exit 1; }
    temporal operator cluster health \
        --address temporal.5xx.engineer:443 \
        --tls \
        --tls-cert-path "${out}/tls.crt" \
        --tls-key-path "${out}/tls.key" \
        --tls-ca-path "${out}/ca.crt" \
        --tls-server-name temporal.5xx.engineer
