# Blog K8s deployment management

# Deploy blog to k8s
apply:
    kubectl apply -k overlays/production

# Delete blog deployment (keeps namespace)
delete:
    kubectl delete -k overlays/production --ignore-not-found=true

# Get blog pod status
status:
    kubectl get pods -n blog

# View blog logs
logs:
    kubectl logs -n blog -l app=blog -f

# Restart blog deployment (pulls latest image)
restart:
    kubectl rollout restart deployment/blog -n blog

# Get all blog resources
get-all:
    kubectl get all,ingress -n blog

# Describe blog deployment
describe:
    kubectl describe deployment/blog -n blog

# Check certificate status
cert-status:
    kubectl get certificate -n blog

# Describe certificate details
cert-describe:
    kubectl describe certificate -n blog

# Full cert status (all resources)
cert-debug:
    #!/usr/bin/env bash
    echo "=== Certificates ==="
    kubectl get certificate -n blog
    echo ""
    echo "=== Challenges ==="
    kubectl get challenge -n blog
    echo ""
    echo "=== Orders ==="
    kubectl get order -n blog

# Clean up everything including namespace
clean:
    kubectl delete namespace blog --ignore-not-found=true
