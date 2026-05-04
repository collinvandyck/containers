# Temporal

Self-hosted Temporal OSS deployment, backed by Postgres, with mTLS-protected gRPC frontend and OAuth-gated Web UI.

## Layout

- `postgres/` — Postgres 16 StatefulSet + headless Service backing both the `temporal` and `temporal_visibility` databases
- `certs/` — SelfSigned bootstrap ClusterIssuer, the `temporal-ca` CA Certificate + Issuer, the frontend server cert, and the in-cluster Web UI client cert
- `temporal-values.yaml` — values for the upstream `temporalio/helm-charts` chart
- `ui/` — oauth2-proxy + Traefik ingress for the Web UI
- `frontend-ingress.yaml` — Traefik IngressRouteTCP (SNI passthrough) for the external mTLS gRPC frontend

## Endpoints

- `temporal.5xx.engineer:443` — gRPC frontend, mTLS required, TCP passthrough through Traefik (clients use **:443**, not :7233 — SNI routing on the existing websecure entrypoint)
- `temporal-ui.5xx.engineer` — Web UI, HTTPS via Traefik, gated by oauth2-proxy with a Google email allowlist

## Required environment variables

Set in `.envrc`:

- `TEMPORAL_POSTGRES_PASSWORD` — password for the `temporal` Postgres role
- `TEMPORAL_OAUTH_CLIENT_ID` — Google OAuth client ID for the Temporal Web UI (create a dedicated client in GCP, separate from Grafana's)
- `TEMPORAL_OAUTH_CLIENT_SECRET` — Google OAuth client secret
- `TEMPORAL_OAUTH_COOKIE_SECRET` — random session cookie key. Generate with: `openssl rand -base64 32 | tr -- '+/' '-_' | tr -d '='`

The OAuth client's authorized redirect URI must include `https://temporal-ui.5xx.engineer/oauth2/callback`.

The email allowlist for the Web UI lives in `ui/oauth2-proxy-emails.yaml` — edit and re-apply to add or remove users.

## Bring-up

```bash
just create-namespace
just create-secrets          # postgres password
just apply-postgres
just apply-certs             # CA + frontend cert
just apply-ui-client-cert    # client cert for the in-cluster Web UI

just add-helm-repo
just helm-template           # sanity-check rendered manifests
just helm-install            # schema setup runs as a pre-install hook

just helm-status
just status

# Web UI
just create-oauth-secret
just apply-ui

# External gRPC ingress
just apply-frontend-ingress
just gen-client-cert laptop
just check-frontend laptop          # smoke test against temporal.5xx.engineer:443
```

## DNS

`temporal.5xx.engineer` and `temporal-ui.5xx.engineer` need to resolve to the cluster's external IP. If you have a wildcard `*.5xx.engineer` record, you're done; otherwise add A/AAAA records for both.

## Connecting workers

```sh
# Local
temporal workflow list \
    --address temporal.5xx.engineer:443 \
    --tls \
    --tls-cert-path ~/.temporal/laptop/tls.crt \
    --tls-key-path ~/.temporal/laptop/tls.key \
    --tls-ca-path ~/.temporal/laptop/ca.crt \
    --tls-server-name temporal.5xx.engineer
```

Cluster workers should mount their `client-<name>-tls` Secret at `/etc/temporal/tls/client/` and connect to `temporal-frontend.temporal.svc.cluster.local:7233` with `TEMPORAL_TLS_SERVER_NAME=temporal-frontend.temporal.svc.cluster.local`.

## Client certificates

Issue a client cert for a worker or local CLI identity:

```bash
just gen-client-cert worker-foo
# writes ~/.temporal/worker-foo/{tls.crt, tls.key, ca.crt}
```

Cluster workers should consume `client-<name>-tls` Secrets directly via volume mounts instead of going through the local export.

There is no CRL/OCSP wired up. `just delete-client-cert <name>` prevents future use of the key material but does not revoke sessions already established with that cert; rely on cert lifetimes (1 year) and CA rotation if you need stronger guarantees.
