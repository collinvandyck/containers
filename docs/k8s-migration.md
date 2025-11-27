# K8s Migration from Docker Compose VPS

Migration of services from the old VPS docker-compose deployment to k8s on the new host (5.78.150.166).

## Completed Migrations

### atuin (k8s/atuin)
- **Domain**: atuin.5xx.engineer
- **Components**: atuin server + postgres statefulset
- **Data**: Migrated via pg_dump/restore (`just migrate`)
- **Notes**: First migration, used `atuin-new.5xx.engineer` as staging domain during cutover

### blog (k8s/blog)
- **Domains**: 5xx.engineer, www.5xx.engineer (redirects to apex)
- **Components**: Jekyll static site baked into caddy image
- **Image**: collinvandyck/blog (Docker Hub)
- **Notes**: Also uses `blog.5xx.engineer` as alternate domain

### static-sites (k8s/static-sites)
- **Domains**:
  - resume.5xx.engineer
  - dotfiles.5xx.engineer
  - boundaq.com, www.boundaq.com (redirects to apex)
- **Components**: Single caddy container serving multiple virtual hosts
- **Image**: ghcr.io/collinvandyck/static-sites

## Remaining Services on Old VPS

| Service | Domain | Migration Complexity | Notes |
|---------|--------|---------------------|-------|
| freshrss | rss.5xx.engineer | Easy | Persistent data for feeds/extensions |
| grafana | grafana.5xx.engineer | Medium | Part of monitoring stack |
| prometheus | (internal) | Medium | 730d retention, large data volume |
| loki | (internal) | Medium | Log aggregation |
| promtail | (internal) | Medium | Becomes DaemonSet in k8s |
| homepage | home.5xx.engineer | Tricky | Needs docker.sock for container stats |
| portainer | portainer.5xx.engineer | Skip | Docker-specific, not useful for k8s |
| glances | glances.neon-stargazer.ts.net | Skip | Host monitoring, needs pid:host |
| pihole | pihole.neon-stargazer.ts.net | Tricky | DNS on port 53, Tailscale-only |

## Shared Resources

### ghcr-secret
Registry credentials for pulling private images from ghcr.io. Created per-namespace:

```bash
# From repo root
just create-ghcr-secret <namespace>
```

Requires `GHCR_PAT` environment variable.

### ClusterIssuers
Let's Encrypt certificate issuers (created via deadswitch repo):
- `letsencrypt-prod` - production certificates
- `letsencrypt-staging` - for testing (certs not trusted by browsers)

## DNS Notes

- Wildcard `*.5xx.engineer` points to new VPS (5.78.150.166)
- Apex `5xx.engineer` and `www` also point to new VPS
- boundaq.com DNS managed separately (needs A records for apex and www)
- Old VPS: 5.161.109.107 (still serves some services)

## Lessons Learned

1. **TTL matters**: Old DNS records with 86400 TTL (24 hours) caused delays in cert issuance. Lower TTL before migrations.

2. **Staging domains**: Using `*-new.5xx.engineer` pattern for parallel testing before cutover works well.

3. **cert-manager self-check**: cert-manager validates challenges externally before notifying Let's Encrypt. If cluster DNS is stale, self-checks fail even if LE would succeed.

4. **Image pull secrets**: ghcr.io private images require `imagePullSecrets` in deployments and `ghcr-secret` in each namespace.
