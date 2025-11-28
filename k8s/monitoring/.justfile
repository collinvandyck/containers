# Monitoring stack K8s deployment management

# Create the monitoring namespace
create-namespace:
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Create Grafana admin credentials secret
# Requires GRAFANA_ADMIN_PASSWORD environment variable
create-grafana-admin-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
        echo "Error: GRAFANA_ADMIN_PASSWORD environment variable is required"
        exit 1
    fi
    kubectl create secret generic grafana-admin-credentials \
        --namespace monitoring \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created grafana-admin-credentials secret"

# Create Grafana OAuth credentials secret
# Requires GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables
create-grafana-oauth-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${GOOGLE_CLIENT_ID:-}" ] || [ -z "${GOOGLE_CLIENT_SECRET:-}" ]; then
        echo "Error: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables are required"
        exit 1
    fi
    kubectl create secret generic grafana-oauth-credentials \
        --namespace monitoring \
        --from-literal=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
        --from-literal=GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created grafana-oauth-credentials secret"

# Create all monitoring secrets
# Requires: GRAFANA_ADMIN_PASSWORD, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
create-secrets: create-namespace create-grafana-admin-secret create-grafana-oauth-secret
    @echo "All monitoring secrets created"

# List secrets in monitoring namespace
list-secrets:
    kubectl get secrets -n monitoring

# Add Helm repositories for monitoring stack
add-repos:
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add grafana https://grafana.github.io/helm-charts || true
    helm repo update

# Install kube-prometheus-stack
# Requires: ALERTMANAGER_SMTP_USERNAME, ALERTMANAGER_SMTP_PASSWORD
install-prometheus:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${ALERTMANAGER_SMTP_USERNAME:-}" ] || [ -z "${ALERTMANAGER_SMTP_PASSWORD:-}" ]; then
        echo "Error: ALERTMANAGER_SMTP_USERNAME and ALERTMANAGER_SMTP_PASSWORD environment variables are required"
        exit 1
    fi
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values base/prometheus-values.yaml \
        --values overlays/production/patches/prometheus-values-patch.yaml \
        --set alertmanager.smtp.username="${ALERTMANAGER_SMTP_USERNAME}" \
        --set alertmanager.smtp.password="${ALERTMANAGER_SMTP_PASSWORD}" \
        --wait

# Install loki-stack
install-loki:
    helm upgrade --install loki-stack grafana/loki-stack \
        --namespace monitoring \
        --values base/loki-values.yaml \
        --wait

# Deploy Grafana ingress
deploy-ingress:
    kubectl apply -f overlays/production/grafana-ingress.yaml

# Deploy AlertManager dashboard ConfigMap
deploy-dashboards:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl create configmap alertmanager-overview-dashboard \
        --namespace monitoring \
        --from-file=alertmanager-alerts.json=base/dashboards/alertmanager-alerts.json \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl label configmap alertmanager-overview-dashboard \
        --namespace monitoring \
        grafana_dashboard=1 \
        --overwrite
    echo "Deployed alertmanager-overview-dashboard"

# Full monitoring stack installation
# Requires all environment variables: GRAFANA_ADMIN_PASSWORD, GOOGLE_CLIENT_ID,
# GOOGLE_CLIENT_SECRET, ALERTMANAGER_SMTP_USERNAME, ALERTMANAGER_SMTP_PASSWORD
install: create-secrets add-repos install-prometheus install-loki deploy-ingress deploy-dashboards
    @echo "Monitoring stack installation complete!"
    @echo "Grafana will be available at https://grafana.5xx.engineer once DNS is configured"

# Uninstall the monitoring stack (keeps namespace)
uninstall:
    helm uninstall loki-stack --namespace monitoring || true
    helm uninstall kube-prometheus-stack --namespace monitoring || true
    @echo "Monitoring stack uninstalled"

# Clean up everything including namespace (WARNING: deletes all data)
clean:
    helm uninstall loki-stack --namespace monitoring || true
    helm uninstall kube-prometheus-stack --namespace monitoring || true
    kubectl delete namespace monitoring || true
    @echo "Monitoring stack and namespace deleted"

# Get monitoring pod status
status:
    @echo "=== Helm Releases ==="
    helm list -n monitoring
    @echo ""
    @echo "=== Pods ==="
    kubectl get pods -n monitoring
    @echo ""
    @echo "=== Services ==="
    kubectl get svc -n monitoring
    @echo ""
    @echo "=== Ingress ==="
    kubectl get ingress -n monitoring

# Get all monitoring resources
get-all:
    kubectl get all,ingress,pvc,configmap -n monitoring

# Port-forward Grafana for local access
grafana-forward:
    @echo "Grafana available at http://localhost:3000"
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Port-forward Prometheus for local access
prometheus-forward:
    @echo "Prometheus available at http://localhost:9090"
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Port-forward AlertManager for local access
alertmanager-forward:
    @echo "AlertManager available at http://localhost:9093"
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# View Grafana logs
logs-grafana:
    kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f

# View Prometheus logs
logs-prometheus:
    kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -f --container prometheus

# View AlertManager logs
logs-alertmanager:
    kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -f --container alertmanager

# View Loki logs
logs-loki:
    kubectl logs -n monitoring -l app=loki -f

# Restart Grafana
restart-grafana:
    kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring

# Check certificate status
cert-status:
    kubectl get certificate -n monitoring

# Describe certificate details
cert-describe:
    kubectl describe certificate -n monitoring

# Full cert debug
cert-debug:
    #!/usr/bin/env bash
    echo "=== Certificate ==="
    kubectl get certificate -n monitoring
    echo ""
    echo "=== Challenge ==="
    kubectl get challenge -n monitoring 2>/dev/null || echo "No challenges"
    echo ""
    echo "=== Order ==="
    kubectl get order -n monitoring 2>/dev/null || echo "No orders"

# Upgrade kube-prometheus-stack (after changing values)
upgrade-prometheus:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${ALERTMANAGER_SMTP_USERNAME:-}" ] || [ -z "${ALERTMANAGER_SMTP_PASSWORD:-}" ]; then
        echo "Error: ALERTMANAGER_SMTP_USERNAME and ALERTMANAGER_SMTP_PASSWORD environment variables are required"
        exit 1
    fi
    helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values base/prometheus-values.yaml \
        --values overlays/production/patches/prometheus-values-patch.yaml \
        --set alertmanager.smtp.username="${ALERTMANAGER_SMTP_USERNAME}" \
        --set alertmanager.smtp.password="${ALERTMANAGER_SMTP_PASSWORD}"

# Upgrade loki-stack (after changing values)
upgrade-loki:
    helm upgrade loki-stack grafana/loki-stack \
        --namespace monitoring \
        --values base/loki-values.yaml
