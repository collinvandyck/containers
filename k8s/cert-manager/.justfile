# cert-manager ClusterIssuers for Let's Encrypt

# Check if cert-manager is installed
check:
    @kubectl get deployment -n cert-manager cert-manager >/dev/null 2>&1 \
        && echo "cert-manager is installed" \
        || echo "cert-manager is NOT installed - run: just install-cert-manager"

# Install cert-manager via Helm
install-cert-manager:
    helm repo add jetstack https://charts.jetstack.io || true
    helm repo update
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait
    @echo "cert-manager installed successfully"

# Upgrade cert-manager via Helm
upgrade-cert-manager:
    helm repo update
    helm upgrade cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set crds.enabled=true \
        --wait

# Uninstall cert-manager (WARNING: will break certificate renewals)
uninstall-cert-manager:
    helm uninstall cert-manager --namespace cert-manager
    kubectl delete namespace cert-manager --ignore-not-found=true

# Deploy production ClusterIssuer (Let's Encrypt)
deploy-prod:
    kubectl apply -f letsencrypt-prod.yaml

# Deploy staging ClusterIssuer (Let's Encrypt - for testing)
deploy-staging:
    kubectl apply -f letsencrypt-staging.yaml

# Deploy both ClusterIssuers
deploy: deploy-prod deploy-staging
    @echo "ClusterIssuers deployed"

# Full install: cert-manager + ClusterIssuers
install: install-cert-manager deploy
    @echo "cert-manager and ClusterIssuers installed"

# Delete ClusterIssuers (keeps cert-manager)
delete:
    kubectl delete -f letsencrypt-prod.yaml --ignore-not-found=true
    kubectl delete -f letsencrypt-staging.yaml --ignore-not-found=true

# Show ClusterIssuers status
status:
    @echo "=== cert-manager pods ==="
    kubectl get pods -n cert-manager
    @echo ""
    @echo "=== ClusterIssuers ==="
    kubectl get clusterissuer

# Describe ClusterIssuers
describe:
    kubectl describe clusterissuer letsencrypt-prod
    @echo ""
    kubectl describe clusterissuer letsencrypt-staging

# Show all certificates across namespaces
certs:
    kubectl get certificates -A

# Show certificate requests
requests:
    kubectl get certificaterequest -A

# Show cert-manager logs
logs:
    kubectl logs -n cert-manager -l app.kubernetes.io/component=controller -f
