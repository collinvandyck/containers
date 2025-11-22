# Atuin Server K8s Deployment

Atuin shell history sync server running on k3s.

## Architecture

- **Namespace**: `atuin`
- **Components**: Atuin server (18.4.0) + Postgres 14
- **Domain**: `atuin-new.5xx.engineer` (migration), `atuin.5xx.engineer` (final)
- **Storage**: 10Gi persistent volume for postgres data

## Prerequisites

1. K8s cluster with cert-manager and traefik ingress controller
2. DNS: `atuin-new.5xx.engineer` → cluster IP
3. Secrets created (see below)

## Secrets Setup

Create required secrets in the `atuin` namespace:

```bash
# Create namespace
kubectl create namespace atuin

# Create postgres password secret
kubectl create secret generic atuin-postgres-secrets \
  --from-literal=POSTGRES_PASSWORD=<your-postgres-password> \
  -n atuin

# Create atuin database URI secret
kubectl create secret generic atuin-secrets \
  --from-literal=ATUIN_DB_URI=postgresql://atuin:<your-postgres-password>@postgres:5432/atuin \
  -n atuin
```

## Deployment

```bash
# Deploy everything
kubectl apply -k overlays/production

# Check status
kubectl get pods -n atuin
kubectl get ingress -n atuin

# View logs
kubectl logs -n atuin -l app=atuin -f
```

## Database Migration

To migrate data from docker-compose postgres:

```bash
# Export from docker-compose
docker-compose exec atuin-db pg_dump -U atuin atuin > atuin_backup.sql

# Import to k8s
kubectl exec -i postgres-0 -n atuin -- psql -U atuin atuin < atuin_backup.sql
```

## Access

- **Database**: `kubectl exec -it -n atuin postgres-0 -- psql -U atuin atuin`
- **Server logs**: `kubectl logs -n atuin -l app=atuin -f`
- **Web UI**: https://atuin-new.5xx.engineer

## Switching to Final Domain

After testing with `atuin-new.5xx.engineer`:

1. Edit `overlays/production/ingress.yaml`
2. Change `atuin-new.5xx.engineer` to `atuin.5xx.engineer`
3. Reapply: `kubectl apply -k overlays/production`
4. Update DNS if needed

## Resources

- Atuin: 256Mi-512Mi RAM, 100m-500m CPU
- Postgres: 256Mi-512Mi RAM, 100m-500m CPU
- Storage: 10Gi PVC

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n atuin

# Describe pods
kubectl describe pod -n atuin <pod-name>

# Check PVC status
kubectl get pvc -n atuin

# Check secrets
kubectl get secrets -n atuin
```
