# Static sites K8s deployment management

image_name := "ghcr.io/collinvandyck/static-sites"

# Build the docker image
build:
    docker build -t {{image_name}}:latest docker/

# Build for linux/amd64 (for pushing to registry)
build-amd64:
    docker buildx build --platform linux/amd64 -t {{image_name}}:latest docker/

# Push image to ghcr.io
push: build-amd64
    docker push {{image_name}}:latest

# Deploy to k8s (build, push, apply, restart)
deploy: push apply restart

# Apply k8s manifests
apply:
    kubectl apply -k overlays/production

# Delete deployment (keeps namespace)
delete:
    kubectl delete -k overlays/production --ignore-not-found=true

# Get pod status
status:
    kubectl get pods -n static-sites

# View logs
logs:
    kubectl logs -n static-sites -l app=static-sites -f

# Restart deployment (pulls latest image)
restart:
    kubectl rollout restart deployment/static-sites -n static-sites

# Get all resources
get-all:
    kubectl get all,ingress,certificate -n static-sites

# Describe deployment
describe:
    kubectl describe deployment/static-sites -n static-sites

# Check certificate status
cert-status:
    kubectl get certificate -n static-sites

# Describe certificates
cert-describe:
    kubectl describe certificate -n static-sites

# Check challenges
cert-challenges:
    kubectl get challenges -n static-sites

# Full cert debug
cert-debug:
    #!/usr/bin/env bash
    echo "=== Certificates ==="
    kubectl get certificate -n static-sites
    echo ""
    echo "=== Challenges ==="
    kubectl get challenges -n static-sites
    echo ""
    echo "=== Orders ==="
    kubectl get orders -n static-sites

# Clean up everything including namespace
clean:
    kubectl delete namespace static-sites --ignore-not-found=true

# Test locally (run container on port 8080)
test-local: build
    docker run --rm -p 8080:8080 {{image_name}}:latest
