app-name := "learn-app"

# Build and push API image
build-api:
    cd services/api && \
    docker build --platform linux/amd64 -t ghcr.io/collinvandyck/k8s-learn-api:latest . && \
    docker push ghcr.io/collinvandyck/k8s-learn-api:latest

# Build and push worker image
build-worker:
    cd services/worker && \
    docker build --platform linux/amd64 -t ghcr.io/collinvandyck/k8s-learn-worker:latest . && \
    docker push ghcr.io/collinvandyck/k8s-learn-worker:latest

yaml:
    helm template {{app-name}} ./helm-chart -n learn

dry-run:
    helm install {{app-name}} ./helm-chart -n learn --dry-run=client

install:
    helm install {{app-name}} ./helm-chart -n learn

uninstall:
    helm uninstall {{app-name}} -n learn

upgrade:
    helm upgrade {{app-name}} ./helm-chart -n learn

