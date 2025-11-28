# Kubernetes Monitoring Stack Migration Plan

This document outlines the plan to extract the generic monitoring infrastructure from the deadswitch project into a shared, reusable monitoring stack in this repository, while providing a clean pattern for applications to integrate their own alerts, dashboards, and service monitors.

## Overview

### Current State

The monitoring stack in `~/code/deadswitch/cluster/monitoring/` is a complete observability solution consisting of:

- **Prometheus** (kube-prometheus-stack Helm chart) - metrics collection
- **Grafana** - visualization and dashboards
- **Loki** (loki-stack Helm chart) - log aggregation
- **AlertManager** - alert routing and notifications
- **Promtail** - log shipping from all pods

This stack is tightly coupled to deadswitch with:
- Hardcoded email addresses (collinvandyck@gmail.com)
- Hardcoded domain (grafana.deadswitch.net)
- Deadswitch-specific alerts, dashboards, and ServiceMonitor living alongside generic infrastructure
- SMTP credentials passed via Helm `--set` flags

### Goals

1. **Extract generic infrastructure** into `k8s/monitoring/` in this repository
2. **Make configuration parameterized** for reuse across deployments
3. **Define a clear pattern** for applications to add their own:
   - ServiceMonitors
   - PrometheusRules (alerts)
   - Grafana dashboards
4. **Maintain backwards compatibility** with deadswitch during migration

## Architecture

### Monitoring Stack Components

```
k8s/monitoring/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-values.yaml       # kube-prometheus-stack Helm values
│   ├── loki-values.yaml             # loki-stack Helm values
│   ├── grafana-ingress.yaml         # Optional: public access
│   └── dashboards/
│       └── alertmanager-alerts.json # Generic AlertManager dashboard
└── overlays/
    └── production/
        ├── kustomization.yaml
        ├── config.env                # Environment-specific config
        └── patches/
            └── prometheus-values-patch.yaml
```

### Application Integration Pattern

Applications integrate with the monitoring stack by deploying their own resources **in their own namespace** (or in the `monitoring` namespace for alerts/dashboards):

```
# In application's k8s directory (e.g., deadswitch/k8s/)
k8s/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── servicemonitor.yaml          # Scrape config for this app
└── monitoring/
    ├── alerts.yaml                  # PrometheusRule for this app
    └── dashboards/
        └── app-dashboard.json       # Grafana dashboard ConfigMap
```

## Implementation Plan

### Phase 1: Extract Generic Monitoring Infrastructure

#### 1.1 Create Directory Structure

Create the monitoring deployment structure:

```
k8s/monitoring/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-values.yaml
│   ├── loki-values.yaml
│   └── dashboards/
│       └── alertmanager-alerts.json
└── overlays/
    └── production/
        ├── kustomization.yaml
        ├── namespace.yaml
        ├── grafana-ingress.yaml
        └── secrets/
            └── README.md            # Instructions for creating secrets
```

#### 1.2 Parameterize prometheus-values.yaml

Extract configurable values from the deadswitch prometheus-values.yaml:

| Parameter | Current Value | Parameterization |
|-----------|---------------|------------------|
| `grafana.grafana.ini.server.root_url` | `https://grafana.deadswitch.net` | ConfigMap/patch overlay |
| `grafana.grafana.ini.auth.google.allowed_emails` | `collinvandyck@gmail.com` | ConfigMap/patch overlay |
| `alertmanager.stringConfig` (email recipients) | `collinvandyck@gmail.com` | Helm template values |
| `alertmanager.stringConfig` (subject prefix) | `[Deadswitch]` | Helm template values |
| Retention settings | 90d, 25GB | Keep as reasonable defaults |
| Resource limits | Various | Keep as reasonable defaults |

The base `prometheus-values.yaml` should contain sensible defaults, with environment-specific overrides in overlays.

#### 1.3 Create Helm Installation Scripts

Add to `.justfile`:

```makefile
# Monitoring stack installation
monitoring-namespace:
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

monitoring-create-secrets:
    @echo "Creating Grafana admin credentials..."
    kubectl create secret generic grafana-admin-credentials \
        --namespace monitoring \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    @echo "Creating Grafana OAuth credentials..."
    kubectl create secret generic grafana-oauth-credentials \
        --namespace monitoring \
        --from-literal=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
        --from-literal=GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -

monitoring-install: monitoring-namespace monitoring-create-secrets
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values k8s/monitoring/base/prometheus-values.yaml \
        --values k8s/monitoring/overlays/production/patches/prometheus-values-patch.yaml \
        --set alertmanager.smtp.username="$ALERTMANAGER_SMTP_USERNAME" \
        --set alertmanager.smtp.password="$ALERTMANAGER_SMTP_PASSWORD"
    helm upgrade --install loki-stack grafana/loki-stack \
        --namespace monitoring \
        --values k8s/monitoring/base/loki-values.yaml

monitoring-uninstall:
    helm uninstall loki-stack --namespace monitoring || true
    helm uninstall kube-prometheus-stack --namespace monitoring || true
```

#### 1.4 AlertManager Configuration

The AlertManager configuration should be generic but allow customization. The base config:

- Routes alerts by severity (critical/warning/info)
- Silences noisy k3s-specific alerts (KubeSchedulerDown, etc.)
- Uses inhibit rules to prevent alert storms
- Sends to a configurable email address

Parameterize via Helm `--set` or overlay patches:
- `alertmanager.smtp.username`
- `alertmanager.smtp.password`
- Email recipient addresses
- Subject line prefix (e.g., `[Production]` vs `[Staging]`)

### Phase 2: Define Application Integration Pattern

#### 2.1 ServiceMonitor Convention

Applications expose metrics and create a ServiceMonitor in their namespace:

```yaml
# Example: k8s/base/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp                        # Same as app name
  labels:
    app: myapp
    release: kube-prometheus-stack   # Required for discovery
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: http                       # Must match Service port name
    path: /metrics
    interval: 30s
```

**Requirements for discovery:**
1. Must have label `release: kube-prometheus-stack`
2. Selector must match the Service's pod selector
3. Port name must match the Service's port name

#### 2.2 PrometheusRule Convention

Applications define their alerts as PrometheusRule CRDs:

```yaml
# Example: k8s/monitoring/alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: monitoring              # Must be in monitoring namespace
  labels:
    prometheus: kube-prometheus-stack-prometheus
    release: kube-prometheus-stack   # Required for discovery
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
        description: "MyApp pod {{ $labels.pod }} is not running"
      expr: |
        kube_pod_status_phase{namespace="myapp",pod=~"myapp-.*",phase!="Running"} == 1
      for: 2m
      labels:
        severity: critical
        component: infrastructure
```

**Alert naming conventions:**
- Alert name prefix: `{AppName}{AlertType}` (e.g., `DeadswitchPodDown`)
- Groups: `{appname}.application` and `{appname}.infrastructure`
- Required labels: `severity` (critical/warning/info), `component`
- Required annotations: `summary`, `description`
- Optional: `runbook_url`

#### 2.3 Dashboard Convention

Applications provide Grafana dashboards as ConfigMaps:

```yaml
# Example: k8s/monitoring/dashboards/myapp-dashboard-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"           # Required for sidecar discovery
    app: myapp
data:
  myapp-dashboard.json: |
    {
      "title": "MyApp Dashboard",
      ...
    }
```

**Dashboard conventions:**
- ConfigMap in `monitoring` namespace
- Label `grafana_dashboard: "1"` for auto-discovery
- JSON file with standard Grafana dashboard format
- Use variables for namespace filtering: `${namespace}`

### Phase 3: Migration Steps

#### 3.1 Deploy Shared Monitoring Stack

1. Create the monitoring directory structure in this repo
2. Copy and parameterize the values files from deadswitch
3. Create required secrets
4. Install via Helm
5. Verify Prometheus, Grafana, Loki, AlertManager are running

#### 3.2 Migrate Deadswitch-Specific Resources

1. Keep ServiceMonitor in deadswitch's `k8s/base/`
2. Move alerts to deadswitch's `k8s/monitoring/alerts/`
3. Move dashboards to deadswitch's `k8s/monitoring/dashboards/`
4. Update deployment to apply these resources
5. Remove cluster/monitoring directory from deadswitch

#### 3.3 Update Deadswitch Deployment Process

New deadswitch deployment flow:
1. **Prerequisite**: Shared monitoring stack deployed from containers repo
2. `kubectl apply -k k8s/overlays/production` (deploys app + ServiceMonitor)
3. `kubectl apply -f k8s/monitoring/` (deploys alerts + dashboards)

### Phase 4: Documentation and Templates

#### 4.1 Create Template Files

Provide copy-paste templates for new applications:

```
k8s/monitoring/templates/
├── servicemonitor-template.yaml
├── prometheusrule-template.yaml
└── dashboard-configmap-template.yaml
```

#### 4.2 Document Integration Steps

Create `k8s/monitoring/README.md` with:
1. Prerequisites (shared stack must be deployed)
2. How to expose metrics from your application
3. How to create a ServiceMonitor
4. How to create alerts (with examples)
5. How to create dashboards
6. Testing and validation steps

## File Changes Summary

### New Files in containers repo

```
k8s/monitoring/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── prometheus-values.yaml
│   ├── loki-values.yaml
│   └── dashboards/
│       └── alertmanager-alerts.json
├── overlays/
│   └── production/
│       ├── kustomization.yaml
│       ├── grafana-ingress.yaml
│       └── patches/
│           └── prometheus-values-patch.yaml
├── templates/
│   ├── servicemonitor-template.yaml
│   ├── prometheusrule-template.yaml
│   └── dashboard-configmap-template.yaml
└── README.md
```

### Changes to deadswitch repo

```
# Move from cluster/monitoring/ to k8s/monitoring/
cluster/monitoring/alerts/deadswitch-alerts.yaml    → k8s/monitoring/alerts.yaml
cluster/monitoring/dashboards/deadswitch.json       → k8s/monitoring/dashboards/deadswitch-dashboard.json

# Keep in place
k8s/base/servicemonitor.yaml                        # No change

# Delete (moved to containers)
cluster/monitoring/prometheus-values.yaml           # Delete
cluster/monitoring/loki-values.yaml                 # Delete
cluster/monitoring/alertmanager-config.yaml         # Delete
cluster/monitoring/grafana-ingress.yaml             # Delete
cluster/monitoring/dashboards/alertmanager-alerts.json  # Move to containers
```

## Environment Variables Required

For the monitoring stack deployment:

| Variable | Description | Used By |
|----------|-------------|---------|
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | grafana-admin-credentials secret |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID | grafana-oauth-credentials secret |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret | grafana-oauth-credentials secret |
| `ALERTMANAGER_SMTP_USERNAME` | Gmail account for sending alerts | Helm --set |
| `ALERTMANAGER_SMTP_PASSWORD` | Gmail app password | Helm --set |
| `ALERTMANAGER_EMAIL_TO` | Alert recipient email | Helm --set or patch |
| `GRAFANA_ROOT_URL` | Public Grafana URL | Overlay patch |
| `GRAFANA_ALLOWED_EMAILS` | OAuth allowed emails | Overlay patch |

## Future Considerations

### Multi-Environment Support

The overlay pattern supports multiple environments:

```
k8s/monitoring/overlays/
├── production/
│   └── patches/prometheus-values-patch.yaml
└── staging/
    └── patches/prometheus-values-patch.yaml
```

### Scaling Considerations

Current configuration is sized for a single-node k3s cluster:
- Prometheus: 30Gi storage, 90d retention
- Loki: 10Gi storage, 7d retention
- AlertManager: 2Gi storage

For larger deployments, consider:
- Remote write to long-term storage (Thanos, Cortex, Mimir)
- Loki in distributed mode
- Higher resource limits

### Additional Integrations

Potential future additions:
- PagerDuty integration for critical alerts
- Slack notifications
- Grafana OnCall
- Tempo for distributed tracing
- Pyroscope for continuous profiling

## Validation Checklist

After migration, verify:

- [ ] Prometheus scraping all expected targets (`Status > Targets`)
- [ ] Grafana accessible and dashboards loading
- [ ] Loki receiving logs (`Explore > Loki > {namespace="monitoring"}`)
- [ ] AlertManager routing configured (`Status > Runtime Configuration`)
- [ ] Test alert fires and email received
- [ ] Application ServiceMonitors discovered
- [ ] Application alerts loaded in Prometheus
- [ ] Application dashboards visible in Grafana
