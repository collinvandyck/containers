# cert-manager & Let's Encrypt ClusterIssuers

Shared cert-manager configuration for automatic TLS certificate provisioning via Let's Encrypt.

## Prerequisites

cert-manager must be installed in the cluster. If not already installed:

```bash
just install-cert-manager
```

## ClusterIssuers

Two ClusterIssuers are provided:

- **letsencrypt-prod** - Production certificates (use for real deployments)
- **letsencrypt-staging** - Staging certificates (use for testing, avoids rate limits)

## Installation

From this directory:

```bash
# Deploy both ClusterIssuers
just deploy

# Or individually:
just deploy-prod
just deploy-staging
```

## Usage

Reference the ClusterIssuer in your Ingress annotations:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

cert-manager will automatically:
1. Detect the annotation
2. Create a Certificate resource
3. Perform HTTP-01 challenge via Traefik
4. Store the certificate in the specified secret
5. Renew before expiration

## Management

```bash
just status      # Show ClusterIssuers
just describe    # Detailed ClusterIssuer info
just certs       # Show all certificates
just requests    # Show certificate requests
just logs        # cert-manager logs
```

## Troubleshooting

### Certificate not issuing

1. Check certificate status:
   ```bash
   kubectl get certificate -n <namespace>
   kubectl describe certificate <name> -n <namespace>
   ```

2. Check certificate request:
   ```bash
   kubectl get certificaterequest -n <namespace>
   kubectl describe certificaterequest <name> -n <namespace>
   ```

3. Check challenges:
   ```bash
   kubectl get challenge -n <namespace>
   kubectl describe challenge <name> -n <namespace>
   ```

4. Check cert-manager logs:
   ```bash
   just logs
   ```

### Common issues

- **DNS not resolving**: Ensure DNS points to your cluster's ingress IP
- **Rate limited**: Use staging issuer for testing, switch to prod when ready
- **Challenge failed**: Ensure Traefik ingress is accessible on port 80
