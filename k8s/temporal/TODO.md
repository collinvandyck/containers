# Temporal — followups

Things identified during the initial bring-up that were intentionally deferred. Not in priority order.

## Hardening

- **NetworkPolicies.** No in-cluster restrictions today. Anything in the k3s cluster can reach `postgres:5432`, `temporal-internal-frontend:7236`, and `temporal-web:8080` with no auth. Fine for a single-user cluster; revisit if anything else lands here. Recommended policy: deny by default in `temporal` ns, allow `oauth2-proxy → temporal-web`, allow temporal pods → postgres, allow internal traffic among temporal services.
- **Rate limiting on ingresses.** No Traefik rate-limit middleware on either `temporal-ui` (HTTPS) or `temporal-frontend` (TCP passthrough). Cheap to add; worth doing before publishing the OAuth app or sharing client certs widely.
- **cert-manager rotationPolicy.** Currently relying on the v1.18+ default (`Always`) for everything, which prints a warning on apply and rotates the CA's private key every renewal. Set explicitly: `Never` on `temporal-ca` so the CA key is stable across the 10-year lifetime; `Always` on the frontend and client certs to silence the warning.
- **Client cert revocation.** No CRL/OCSP. `delete-client-cert` removes the secret but in-flight sessions are unaffected. Acceptable given the 1-year leaf-cert lifetime; revisit if certs ever land on shared/untrusted machines.

## Functionality

- **Cluster-resident worker pattern.** The `example/` workflow runs from the laptop only. Add a Deployment example that mounts a `client-<name>-tls` Secret at `/etc/temporal/tls/client/`, connects to `temporal-frontend.temporal.svc.cluster.local:7233`, and registers workflows. Probably belongs under `example/cluster/` or similar.
- **Postgres backups.** Single Postgres StatefulSet, no backups. CronJob that `pg_dump`s to a PVC (or out to object storage) is the obvious move. Deferred when first discussed as out of scope for v1.
- **Pin the temporal helm chart version.** `helm-install` recipe currently tracks whatever the latest in the temporalio repo is. Pin to `--version <x.y.z>` so cluster upgrades are deliberate.

## Auth (later, when needed)

- **Cert-based namespace authz (claim mapper).** Decided to skip for v1 — every authenticated client is effectively admin. When you start running >1 worker identity and want "worker-foo can only touch namespace X," wire up `server.config.authorization.claimMapper` against the cert's CN/Organization. Our client certs already set `commonName: <name>` and `subject.organizations: [temporal-clients]` so the data is there.
- **oauth2-proxy reusability.** Currently lives in the `temporal` namespace and is wired specifically to `temporal-web`. If a second service needs Google OAuth gating, break it out — either move it to its own namespace or duplicate the deployment per service. Single-app per oauth2-proxy is the simplest pattern.

## Nice-to-haves

- **Dedicated TCP entrypoint on :7233.** Today external clients connect on `:443` because we ride the existing websecure entrypoint via SNI. Adding a `temporal` entrypoint to the k3s Traefik HelmChartConfig would let clients use the canonical port. Cosmetic; current setup works.
- **`internode` TLS.** Frontend mTLS only. Traffic between server services (history → matching, etc.) is plaintext inside the cluster. Add `tls.internode` server+client config if you ever want defense-in-depth against an in-namespace attacker.
