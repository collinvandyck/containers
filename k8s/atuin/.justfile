# Atuin K8s deployment management

# VPS host for migration (old docker-compose deployment)
vps_host := "root@5xx.engineer"

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

# ============================================================================
# Migration from VPS docker-compose to k8s
# ============================================================================

# Dump atuin postgres from VPS docker-compose deployment
vps-dump file="vps_atuin_backup.sql":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Dumping atuin database from VPS ({{vps_host}})..."
    ssh {{vps_host}} "docker exec atuin-db pg_dump -U atuin atuin" > {{file}}
    echo "Backup saved to {{file}} ($(wc -c < {{file}} | xargs) bytes)"

# Migrate data from VPS to k8s (dump from VPS, restore to k8s)
migrate:
    #!/usr/bin/env bash
    set -euo pipefail
    backup_file="vps_atuin_backup_$(date +%Y%m%d_%H%M%S).sql"

    echo "=== Atuin Data Migration: VPS -> K8s ==="
    echo ""

    # Step 1: Dump from VPS
    echo "Step 1: Dumping from VPS docker-compose postgres..."
    ssh {{vps_host}} "docker exec atuin-db pg_dump -U atuin atuin" > "$backup_file"
    echo "  Saved to $backup_file ($(wc -c < "$backup_file" | xargs) bytes)"
    echo ""

    # Step 2: Show what we're about to do
    echo "Step 2: Preview - tables in backup:"
    grep -E "^CREATE TABLE|^COPY" "$backup_file" | head -20
    echo ""

    # Step 3: Clear k8s database and restore
    echo "Step 3: Restoring to k8s postgres..."
    echo "  Dropping existing tables..."
    kubectl exec -n atuin postgres-0 -- psql -U atuin atuin -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    echo "  Importing data..."
    kubectl exec -i -n atuin postgres-0 -- psql -U atuin atuin < "$backup_file"
    echo ""

    # Step 4: Verify
    echo "Step 4: Verifying migration..."
    echo "  Row counts:"
    kubectl exec -n atuin postgres-0 -- psql -U atuin atuin -c "SELECT table_name, (xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count FROM (SELECT table_name, query_to_xml(format('SELECT COUNT(*) as cnt FROM %I.%I', table_schema, table_name), false, true, '') as xml_count FROM information_schema.tables WHERE table_schema = 'public') t ORDER BY table_name;"
    echo ""

    echo "=== Migration complete ==="
    echo "Backup file retained at: $backup_file"
    echo ""
    echo "Next steps:"
    echo "  1. Restart atuin: just restart"
    echo "  2. Test sync at https://atuin-new.5xx.engineer"

# Show row counts in k8s postgres
row-counts:
    kubectl exec -n atuin postgres-0 -- psql -U atuin atuin -c "SELECT table_name, (xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count FROM (SELECT table_name, query_to_xml(format('SELECT COUNT(*) as cnt FROM %I.%I', table_schema, table_name), false, true, '') as xml_count FROM information_schema.tables WHERE table_schema = 'public') t ORDER BY table_name;"

# Show row counts in VPS postgres
vps-row-counts:
    ssh {{vps_host}} "docker exec atuin-db psql -U atuin atuin -c \"SELECT table_name, (xpath('/row/cnt/text()', xml_count))[1]::text::int as row_count FROM (SELECT table_name, query_to_xml(format('SELECT COUNT(*) as cnt FROM %I.%I', table_schema, table_name), false, true, '') as xml_count FROM information_schema.tables WHERE table_schema = 'public') t ORDER BY table_name;\""

# Compare row counts between VPS and k8s
compare:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== VPS (source) ==="
    just vps-row-counts
    echo ""
    echo "=== K8s (target) ==="
    just row-counts

# Full deployment: create secrets and apply manifests
deploy: create-secrets apply

# Clean up everything including namespace (WARNING: deletes all data)
clean:
    kubectl delete namespace atuin --ignore-not-found=true

# Check certificate status
cert-status:
    kubectl get certificate -n atuin

# Describe certificate details
cert-describe:
    kubectl describe certificate -n atuin

# Check certificate request status
cert-request:
    kubectl get certificaterequest -n atuin

# Check ACME challenge status
cert-challenge:
    kubectl get challenge -n atuin

# Describe challenge details
cert-challenge-describe:
    kubectl describe challenge -n atuin

# Check ACME order status
cert-order:
    kubectl get order -n atuin

# Describe order details
cert-order-describe:
    kubectl describe order -n atuin

# View cert-manager logs for atuin
cert-logs:
    kubectl logs -n cert-manager -l app=cert-manager --tail=50 | grep -i atuin

# Delete certificate to retry issuance
cert-delete:
    kubectl delete certificate -n atuin atuin-tls

# Full cert status (all resources)
cert-debug:
    #!/usr/bin/env bash
    echo "=== Certificate ==="
    kubectl get certificate -n atuin
    echo ""
    echo "=== Challenge ==="
    kubectl get challenge -n atuin
    echo ""
    echo "=== Order ==="
    kubectl get order -n atuin
    echo ""
    echo "=== Recent cert-manager logs ==="
    kubectl logs -n cert-manager -l app=cert-manager --tail=20 | grep -i atuin
