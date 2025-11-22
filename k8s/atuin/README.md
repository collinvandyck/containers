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

Set the postgres password in your environment (e.g., `.envrc`):

```bash
export ATUIN_POSTGRES_PASSWORD="your-secure-password"
```

Then create secrets using justfile:

```bash
just create-secrets
```

This creates the namespace and both required secrets.

## Deployment

From the `k8s/atuin` directory:

```bash
# Full deployment (creates secrets and applies manifests)
just deploy

# Or step by step
just create-secrets
just apply

# Check status
just status

# View logs
just logs
```

## Database Migration

To migrate data from docker-compose postgres:

```bash
# Export from docker-compose (on old VPS)
docker-compose exec atuin-db pg_dump -U atuin atuin > atuin_backup.sql

# Import to k8s (from this directory)
just restore atuin_backup.sql
```

## Access

- **Database**: `just psql`
- **Server logs**: `just logs`
- **Postgres logs**: `just logs-postgres`
- **Web UI**: https://atuin-new.5xx.engineer

## Common Commands

```bash
just status              # Get pod status
just logs                # View atuin server logs
just psql                # Connect to database
just get-all             # Get all resources
just describe            # Describe atuin deployment
just restart             # Restart deployment
just backup              # Export database to atuin_backup.sql
just restore <file>      # Import database from file
```

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
