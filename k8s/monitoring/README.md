# Kubernetes Monitoring Stack

Shared monitoring infrastructure for all k8s deployments, based on:
- **kube-prometheus-stack** - Prometheus, Grafana, AlertManager, Node Exporter, Kube State Metrics
- **loki-stack** - Loki (log aggregation) + Promtail (log shipping)

## Prerequisites

### Environment Variables

Set these before running installation:

```bash
# Grafana admin password
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

# Google OAuth credentials (for Grafana SSO)
export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="your-client-secret"

# AlertManager SMTP credentials (Gmail app password)
export ALERTMANAGER_SMTP_USERNAME="your-email@gmail.com"
export ALERTMANAGER_SMTP_PASSWORD="your-app-password"
```

### DNS

Configure DNS to point `grafana.5xx.engineer` to your cluster's ingress IP.

## Installation

From the `k8s/monitoring/` directory:

```bash
cd k8s/monitoring

# Full installation (creates secrets, installs Helm charts, deploys ingress)
just install

# Or step by step:
just create-secrets
just add-repos
just install-prometheus
just install-loki
just deploy-ingress
just deploy-dashboards
```

## Access

### Production
- Grafana: https://grafana.5xx.engineer (OAuth login)

### Local (port-forward)
```bash
just grafana-forward      # http://localhost:3000
just prometheus-forward   # http://localhost:9090
just alertmanager-forward # http://localhost:9093
```

## Application Integration

Applications integrate with the monitoring stack by deploying their own:
- **ServiceMonitor** - tells Prometheus where to scrape metrics
- **PrometheusRule** - custom alert definitions
- **Dashboard ConfigMap** - Grafana dashboards

### 1. Expose Metrics

Your application must expose a `/metrics` endpoint in Prometheus format.

### 2. Create a ServiceMonitor

In your application's `k8s/base/` directory:

```yaml
# servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  labels:
    app: myapp
    release: kube-prometheus-stack  # Required for discovery
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: http          # Must match your Service port name
    path: /metrics
    interval: 30s
```

### 3. Create Alerts (Optional)

In your application's `k8s/monitoring/` directory:

```yaml
# alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus-stack-prometheus
    release: kube-prometheus-stack  # Required for discovery
    app: myapp
    role: alert-rules
spec:
  groups:
  - name: myapp.application
    interval: 30s
    rules:
    - alert: MyAppPodDown
      annotations:
        summary: "MyApp pod is down"
        description: "Pod {{ $labels.pod }} is not running"
      expr: |
        kube_pod_status_phase{namespace="myapp",pod=~"myapp-.*",phase!="Running"} == 1
      for: 2m
      labels:
        severity: critical
        component: infrastructure
```

Deploy with: `kubectl apply -f k8s/monitoring/alerts.yaml`

### 4. Create Dashboards (Optional)

```bash
# Create ConfigMap from JSON dashboard
kubectl create configmap myapp-dashboard \
  --namespace monitoring \
  --from-file=myapp.json=k8s/monitoring/dashboards/myapp.json \
  --dry-run=client -o yaml | kubectl apply -f -

# Label it for Grafana sidecar discovery
kubectl label configmap myapp-dashboard \
  --namespace monitoring \
  grafana_dashboard=1
```

## Directory Structure

```
k8s/monitoring/
├── .justfile                         # Just commands for this deployment
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-values.yaml        # Base Helm values
│   ├── loki-values.yaml
│   └── dashboards/
│       └── alertmanager-alerts.json
├── overlays/
│   └── production/
│       ├── kustomization.yaml
│       ├── grafana-ingress.yaml
│       └── patches/
│           └── prometheus-values-patch.yaml  # Production overrides
├── templates/                        # Copy-paste templates for apps
│   ├── servicemonitor-template.yaml
│   ├── prometheusrule-template.yaml
│   └── dashboard-configmap-template.yaml
└── README.md
```

## Management Commands

All commands run from the `k8s/monitoring/` directory:

```bash
just status              # Show pods, services, ingress
just get-all             # Show all resources in monitoring namespace
just list-secrets        # List secrets

just logs-grafana        # View Grafana logs
just logs-prometheus     # View Prometheus logs
just logs-alertmanager   # View AlertManager logs
just logs-loki           # View Loki logs

just restart-grafana     # Restart Grafana deployment

just upgrade-prometheus  # Upgrade after changing values
just upgrade-loki        # Upgrade after changing values

just uninstall           # Remove Helm releases (keeps namespace)
just clean               # Remove everything including namespace
```

## Customization

### Production Overlay

Edit `overlays/production/patches/prometheus-values-patch.yaml` to change:
- Grafana URL (`grafana.grafana.ini.server.root_url`)
- Allowed OAuth emails (`grafana.grafana.ini.auth.google.allowed_emails`)
- Alert email recipient (`alertmanager.smtp.to`)
- Alert subject prefix (`alertmanager.subjectPrefix`)

### Base Values

Edit `base/prometheus-values.yaml` for:
- Retention periods
- Resource limits
- Default alert rules (enable/disable k8s component alerts)
- Scrape intervals
