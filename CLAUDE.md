# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Kubernetes infrastructure repo for personal services running on a K3s cluster. Migrated from Docker Compose on a VPS. Services are deployed via Helm charts and Kustomize overlays. Domain is `*.5xx.engineer`, ingress via Traefik, TLS via cert-manager + Let's Encrypt.

## Common Commands

### Root-level justfile (Helm webapp chart deployments)

```bash
just helm-template <app>       # Preview rendered manifests (e.g. freshrss)
just helm-deploy <app>         # Deploy/upgrade via Helm
just helm-uninstall <app>      # Uninstall (keeps namespace/PVCs)
just helm-logs <app>           # Follow pod logs
just helm-restart <app>        # Rolling restart (re-pulls :latest)
just helm-get <app>            # Show all resources for an app
just helm-list                 # List all Helm releases
just create-ghcr-secret <ns>   # Create image pull secret (needs GHCR_PAT)
```

### Per-app justfiles (run from within `k8s/<app>/`)

Each app directory has its own `.justfile` with app-specific commands like `deploy`, `status`, `logs`, `create-secrets`, etc. Monitoring has the most extensive one with `install`, `upgrade-prometheus`, `upgrade-loki`, port-forwarding, and cert debugging.

## Architecture

### Deployment Strategies

- **Helm webapp chart** (`k8s/charts/webapp/`): Reusable chart for simple apps. Apps like `freshrss` just provide a `values.yaml` in their directory. Deployed with `just helm-deploy <app>`.
- **Kustomize** (`base/` + `overlays/production/`): Used by `atuin`, `blog`, `static-sites`. Deployed with `kubectl apply -k overlays/production`.
- **External Helm charts**: Monitoring stack uses upstream `kube-prometheus-stack` and `loki-stack` charts with local values files.

### Key Directories

- `k8s/charts/webapp/` — shared Helm chart template (deployment, service, ingress, PVC)
- `k8s/monitoring/` — Prometheus, Grafana, Loki, AlertManager (kube-prometheus-stack)
- `k8s/learn/` — example microservices project (Go API + Worker + Redis + Postgres) with its own Helm chart
- `k8s/cert-manager/` — ClusterIssuers for Let's Encrypt (prod + staging)

### Conventions

- Namespace matches app name (e.g. `freshrss` namespace for freshrss)
- Image pull secret is always named `ghcr-secret`
- IngressClassName is `traefik`
- ClusterIssuers: `letsencrypt-prod`, `letsencrypt-staging`
- Secrets are created via justfile recipes from env vars (sourced from `.envrc` via direnv)
- Private images hosted on `ghcr.io/collinvandyck/*`

### Environment

- `.envrc` contains all secrets (DB passwords, GHCR PAT, SMTP creds, Grafana/OAuth creds) — loaded by direnv
- `mise.toml` manages tool versions (currently just Python 3)
- No CI/CD pipeline — deployments are manual via `just` commands
