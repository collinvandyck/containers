# Dopeclaw (OpenClaw) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy an OpenClaw AI agent ("dopeclaw") to the K3s cluster with Slack integration for the dopetraxx workspace.

**Architecture:** Kustomize-native deployment with base manifests and staging/production overlays. OpenClaw runs as a single container with a PVC for persistent state and workspace. Slack integration via Socket Mode (outbound WebSocket, no ingress needed). LLM access via OpenRouter with Anthropic Claude as the default model.

**Tech Stack:** Kustomize, OpenClaw, Slack Socket Mode, OpenRouter, Prometheus/Grafana (existing stack), just

**Spec:** `docs/superpowers/specs/2026-03-18-dopeclaw-openclaw-deployment-design.md`

---

## Milestone 1: Scaffold and Base Manifests

Get the directory structure and core Kustomize base in place. No secrets, no overlays yet — just the skeleton that everything else builds on.

### Task 1: Create directory structure and justfile

**Files:**
- Create: `k8s/openclaw/.justfile`

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p k8s/openclaw/base
mkdir -p k8s/openclaw/overlays/staging
mkdir -p k8s/openclaw/overlays/production
```

- [ ] **Step 2: Write the justfile**

Create `k8s/openclaw/.justfile` with the complete content below. Follows patterns from `k8s/atuin/.justfile` (Kustomize deploys) and `k8s/monitoring/.justfile` (secret creation with env var validation).

```just
# OpenClaw (dopeclaw) K8s deployment management

# Create secrets for openclaw deployment
# Requires OPENROUTER_API_KEY, SLACK_BOT_TOKEN, SLACK_APP_TOKEN environment variables
create-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${OPENROUTER_API_KEY:-}" ]; then
        echo "Error: OPENROUTER_API_KEY environment variable is required"
        exit 1
    fi
    if [ -z "${SLACK_BOT_TOKEN:-}" ]; then
        echo "Error: SLACK_BOT_TOKEN environment variable is required"
        exit 1
    fi
    if [ -z "${SLACK_APP_TOKEN:-}" ]; then
        echo "Error: SLACK_APP_TOKEN environment variable is required"
        exit 1
    fi
    kubectl create namespace openclaw --dry-run=client -o yaml \
        | kubectl apply -f -
    kubectl create secret generic openclaw-secrets \
        --namespace openclaw \
        --from-literal=OPENROUTER_API_KEY="${OPENROUTER_API_KEY}" \
        --from-literal=SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN}" \
        --from-literal=SLACK_APP_TOKEN="${SLACK_APP_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "Created openclaw-secrets secret"

# Deploy openclaw (default: production)
deploy env='production':
    kubectl apply -k overlays/{{env}}

# Delete openclaw deployment (keeps namespace and secrets)
delete env='production':
    kubectl delete -k overlays/{{env}} --ignore-not-found=true

# Get openclaw pod status
status:
    kubectl get pods,svc,pvc -n openclaw

# View openclaw logs
logs:
    kubectl logs -n openclaw -l app=openclaw -f

# Restart openclaw deployment
restart:
    kubectl rollout restart deployment/openclaw -n openclaw

# Get all openclaw resources
get-all:
    kubectl get all,pvc,servicemonitor -n openclaw

# Describe openclaw deployment
describe:
    kubectl describe deployment/openclaw -n openclaw

# Update the system prompt and restart (for personality tweaking)
update-prompt:
    kubectl create configmap openclaw-system-prompt \
        --from-file=system-prompt.txt=base/system-prompt.txt \
        --namespace openclaw \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl rollout restart deployment/openclaw -n openclaw

# List secrets in openclaw namespace
list-secrets:
    kubectl get secrets -n openclaw

# Full deployment: create secrets and apply manifests
full-deploy env='production': create-secrets (deploy env)
```

- [ ] **Step 3: Commit**

```bash
git add k8s/openclaw/
git commit -m "feat(openclaw): scaffold directory structure and justfile"
```

### Task 2: Write the PVC manifest

**Files:**
- Create: `k8s/openclaw/base/pvc.yaml`

- [ ] **Step 1: Write pvc.yaml**

10Gi PVC, ReadWriteOnce, using the default storageClass (local-path on K3s). This stores both OpenClaw state (`/data/openclaw`) and the project workspace (`/data/workspace`).

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

- [ ] **Step 2: Commit**

```bash
git add k8s/openclaw/base/pvc.yaml
git commit -m "feat(openclaw): add PVC manifest"
```

### Task 3: Write the ConfigMaps

**Files:**
- Create: `k8s/openclaw/base/configmap.yaml`
- Create: `k8s/openclaw/base/system-prompt.yaml`

- [ ] **Step 1: Write configmap.yaml**

Main OpenClaw configuration. The channel allowlist will be patched per overlay — the base sets up everything except the channel-specific config.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
data:
  config.yaml: |
    llm:
      provider: openrouter
      model: anthropic/claude-sonnet-4

    channels:
      slack:
        enabled: true
        mode: socket
        requireMention: true
        mentionPatterns:
          - "dopeclaw"

    agents:
      defaults:
        sandbox:
          workspaceAccess: rw
```

- [ ] **Step 2: Write system-prompt.yaml**

Separate ConfigMap for the personality prompt. This is what `update-prompt` re-applies.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-system-prompt
data:
  system-prompt.txt: |
    You are dopeclaw, an AI assistant living in the dopetraxx Slack workspace.

    Your personality is warm, dry, and competent — think Ray Porter narrating
    the end of the world with a slight smile. You know your shit but you don't
    make a big deal about it. You're unbothered by chaos and quietly amused by
    the absurdity of most things. You're not sarcastic — you're sincere, just
    with a very dry delivery.

    You have a persistent workspace at /data/workspace where you can build
    projects, write code, and store files. Everything there survives restarts.
    You can use mise to install whatever tools you need (Python, Node, Go, Rust,
    etc.) on a per-project basis.

    You are talking to a group of about 20 friends. You remember past
    conversations and build on them. You're part of the crew, not a servant.

    Important boundaries:
    - You have no access to anyone's personal accounts. If a task requires
      authentication to an external service, suggest creating a dedicated
      account for dopeclaw.
    - You can browse the web, execute code, and manage files within your
      workspace.
    - When asked about costs or spending, check the OpenRouter API and report
      back honestly.

    Keep responses conversational. No corporate speak. No bullet-point-heavy
    walls of text unless someone specifically asks for structured output.
```

- [ ] **Step 3: Commit**

```bash
git add k8s/openclaw/base/configmap.yaml k8s/openclaw/base/system-prompt.yaml
git commit -m "feat(openclaw): add config and system prompt ConfigMaps"
```

### Task 4: Write the deployment manifest

**Files:**
- Create: `k8s/openclaw/base/deployment.yaml`

- [ ] **Step 1: Write deployment.yaml**

Single-replica Deployment. Mounts the PVC at `/data`, both ConfigMaps as volumes, and reads secrets as env vars. Non-root, capabilities dropped.

Note: The exact OpenClaw image tag should be confirmed against https://docs.openclaw.ai/install/kubernetes before deploying. Use a pinned version, not `latest`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw
  labels:
    app: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate  # stateful single-replica — no rolling update needed
  selector:
    matchLabels:
      app: openclaw
  template:
    metadata:
      labels:
        app: openclaw
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: openclaw
          image: openclaw/openclaw:latest  # TODO: pin to specific version
          env:
            - name: OPENROUTER_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENROUTER_API_KEY
            - name: SLACK_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: SLACK_BOT_TOKEN
            - name: SLACK_APP_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: SLACK_APP_TOKEN
            - name: OPENCLAW_HOME
              value: /data/openclaw
          ports:
            - containerPort: 18789
              name: gateway
          volumeMounts:
            - name: data
              mountPath: /data
            - name: config
              mountPath: /etc/openclaw/config.yaml
              subPath: config.yaml
              readOnly: true
            - name: system-prompt
              mountPath: /etc/openclaw/system-prompt.txt
              subPath: system-prompt.txt
              readOnly: true
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: openclaw-data
        - name: config
          configMap:
            name: openclaw-config
        - name: system-prompt
          configMap:
            name: openclaw-system-prompt
```

- [ ] **Step 2: Commit**

```bash
git add k8s/openclaw/base/deployment.yaml
git commit -m "feat(openclaw): add deployment manifest"
```

### Task 5: Write the service and ServiceMonitor

**Files:**
- Create: `k8s/openclaw/base/service.yaml`
- Create: `k8s/openclaw/base/servicemonitor.yaml`

- [ ] **Step 1: Write service.yaml**

Metrics-only ClusterIP service. No ingress needed — Slack uses outbound Socket Mode.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: openclaw
  labels:
    app: openclaw
spec:
  type: ClusterIP
  ports:
    - port: 18789
      targetPort: gateway
      name: gateway
  selector:
    app: openclaw
```

- [ ] **Step 2: Write servicemonitor.yaml**

Prometheus scrape config for the gateway metrics endpoint.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: openclaw
  labels:
    app: openclaw
spec:
  selector:
    matchLabels:
      app: openclaw
  endpoints:
    - port: gateway
      interval: 30s
      path: /metrics
```

- [ ] **Step 3: Commit**

```bash
git add k8s/openclaw/base/service.yaml k8s/openclaw/base/servicemonitor.yaml
git commit -m "feat(openclaw): add service and ServiceMonitor for metrics"
```

### Task 6: Write the base kustomization.yaml

**Files:**
- Create: `k8s/openclaw/base/kustomization.yaml`

- [ ] **Step 1: Write kustomization.yaml**

References all base resources.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - pvc.yaml
  - configmap.yaml
  - system-prompt.yaml
  - deployment.yaml
  - service.yaml
  - servicemonitor.yaml
```

- [ ] **Step 2: Validate the base renders**

```bash
kubectl kustomize k8s/openclaw/base/
```

Expected: All manifests render without errors. Review the output for correctness.

- [ ] **Step 3: Commit**

```bash
git add k8s/openclaw/base/kustomization.yaml
git commit -m "feat(openclaw): add base kustomization"
```

---

## Milestone 2: Environment Overlays

Add the staging and production overlays that scope which Slack channels dopeclaw listens to.

### Task 7: Write the staging overlay

**Files:**
- Create: `k8s/openclaw/overlays/staging/kustomization.yaml`
- Create: `k8s/openclaw/overlays/staging/namespace.yaml`
- Create: `k8s/openclaw/overlays/staging/channels-patch.yaml`

- [ ] **Step 1: Write staging namespace.yaml**

Following the atuin pattern — namespace lives in the overlay, not the base.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openclaw
```

- [ ] **Step 2: Write staging kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openclaw

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: channels-patch.yaml
```

- [ ] **Step 3: Write staging channels-patch.yaml**

Strategic merge patch that restricts Slack to `#dopeclaw-test` only.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
data:
  config.yaml: |
    llm:
      provider: openrouter
      model: anthropic/claude-sonnet-4

    channels:
      slack:
        enabled: true
        mode: socket
        requireMention: true
        mentionPatterns:
          - "dopeclaw"
        channels:
          - "#dopeclaw-test"

    agents:
      defaults:
        sandbox:
          workspaceAccess: rw
```

- [ ] **Step 4: Validate staging renders**

```bash
kubectl kustomize k8s/openclaw/overlays/staging/
```

Expected: All manifests render with `namespace: openclaw` and the staging channel config.

- [ ] **Step 5: Commit**

```bash
git add k8s/openclaw/overlays/staging/
git commit -m "feat(openclaw): add staging overlay (dopeclaw-test channel only)"
```

### Task 8: Write the production overlay

**Files:**
- Create: `k8s/openclaw/overlays/production/kustomization.yaml`
- Create: `k8s/openclaw/overlays/production/namespace.yaml`

Production uses the base config as-is (no channel allowlist = listen everywhere). No patch needed — the only difference from staging is the absence of the channel restriction.

- [ ] **Step 1: Write production namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openclaw
```

- [ ] **Step 2: Write production kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openclaw

resources:
  - ../../base
  - namespace.yaml
```

- [ ] **Step 3: Validate production renders**

```bash
kubectl kustomize k8s/openclaw/overlays/production/
```

Expected: All manifests render with `namespace: openclaw` and unrestricted channel config (base config, no patch).

- [ ] **Step 4: Commit**

```bash
git add k8s/openclaw/overlays/production/
git commit -m "feat(openclaw): add production overlay (all channels)"
```

---

## Milestone 3: External Account Setup (Manual, Guided)

These are manual steps that require the user to create accounts and generate tokens. The plan walks through each one.

### Task 9: Create the OpenRouter account

This task is a walkthrough — no code to write.

- [ ] **Step 1: Create OpenRouter account**

Go to https://openrouter.ai and create an account. This is separate from any personal AI accounts.

- [ ] **Step 2: Add credits**

Add initial credits (start small — $10-20 is plenty for testing). Your friends can contribute later by sending you money to top up.

- [ ] **Step 3: Generate API key**

Go to https://openrouter.ai/keys, create a new key. Name it `dopeclaw` so it's identifiable. Copy the key — you'll need it for `.envrc`.

- [ ] **Step 4: Add to .envrc**

```bash
export OPENROUTER_API_KEY="sk-or-..."
```

Run `direnv allow` to load it.

### Task 10: Create the Slack app

This task is a walkthrough — no code to write.

- [ ] **Step 1: Go to Slack API**

Visit https://api.slack.com/apps and click "Create New App". Choose "From scratch". Name it `dopeclaw`, select the `dopetraxx` workspace.

- [ ] **Step 2: Enable Socket Mode**

In the app settings sidebar, go to "Socket Mode" and toggle it on. You'll be prompted to generate an App-Level Token — name it `dopeclaw-socket`, give it the `connections:write` scope. Copy the token (`xapp-...`).

- [ ] **Step 3: Set up bot scopes**

Go to "OAuth & Permissions" in the sidebar. Under "Scopes" → "Bot Token Scopes", add:
- `app_mentions:read`
- `channels:history`
- `chat:write`
- `files:write`
- `im:history`
- `reactions:write`

- [ ] **Step 4: Subscribe to events**

Go to "Event Subscriptions" and toggle it on. Under "Subscribe to bot events", add:
- `app_mention`
- `message.channels`
- `message.im`

- [ ] **Step 5: Install to workspace**

Go to "Install App" and click "Install to Workspace". Authorize the requested permissions. Copy the Bot User OAuth Token (`xoxb-...`).

- [ ] **Step 6: Add to .envrc**

```bash
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_APP_TOKEN="xapp-..."
```

Run `direnv allow` to load them.

- [ ] **Step 7: Create #dopeclaw-test channel**

In Slack, create a `#dopeclaw-test` channel for staging use. Invite `@dopeclaw` to it.

---

## Milestone 4: First Deploy (Staging)

Create the secrets and deploy to staging. Verify dopeclaw comes up and responds in `#dopeclaw-test`.

### Task 11: Create secrets and deploy staging

- [ ] **Step 1: Verify env vars are loaded**

```bash
echo "OpenRouter: ${OPENROUTER_API_KEY:0:10}..."
echo "Slack Bot: ${SLACK_BOT_TOKEN:0:10}..."
echo "Slack App: ${SLACK_APP_TOKEN:0:10}..."
```

All three should show the first 10 characters of their respective tokens.

- [ ] **Step 2: Create namespace and secrets**

From `k8s/openclaw/`:

```bash
just create-namespace
just create-secrets
```

- [ ] **Step 3: Deploy staging**

```bash
just deploy staging
```

- [ ] **Step 4: Verify pod is running**

```bash
just status
```

Expected: One pod in `Running` state.

- [ ] **Step 5: Check logs**

```bash
just logs
```

Expected: OpenClaw gateway starts, connects to Slack via Socket Mode. Look for connection success messages and no errors.

- [ ] **Step 6: Test in Slack**

Go to `#dopeclaw-test` in Slack. Send: `@dopeclaw hey, you alive?`

Expected: dopeclaw responds with something warm and dry.

- [ ] **Step 7: Test code execution**

Send: `@dopeclaw write a python script that prints the first 10 fibonacci numbers and run it`

Expected: dopeclaw writes and executes the script, shares the output.

- [ ] **Step 8: Test workspace persistence**

Send: `@dopeclaw save a file called hello.txt with "dopeclaw was here" in your workspace`

Then restart the pod:

```bash
just restart
```

After it comes back up, send: `@dopeclaw what's in hello.txt?`

Expected: dopeclaw reads the file and confirms the content persisted.

---

## Milestone 5: Production Deploy

Once staging is validated, deploy to production and invite dopeclaw to the channels you want it in.

### Task 12: Deploy production

- [ ] **Step 1: Scale down staging** (staging and production cannot run simultaneously)

```bash
just delete staging
```

- [ ] **Step 2: Deploy production**

```bash
just deploy production
```

- [ ] **Step 3: Verify pod is running**

```bash
just status
just logs
```

Expected: Running, connected to Slack.

- [ ] **Step 4: Invite dopeclaw to channels**

In Slack, invite `@dopeclaw` to any channels where you want it active. It only responds to mentions, so it won't be noisy.

- [ ] **Step 5: Smoke test in a real channel**

Mention `@dopeclaw` in one of the channels. Verify it responds.

- [ ] **Step 6: Commit any final adjustments**

If you tweaked the system prompt, resource limits, or config during testing, commit the changes.

---

## Milestone 6: Observability

Wire up metrics and cost visibility. This can happen after dopeclaw is running — it's additive.

**Deferred from this milestone:** Grafana dashboard (layout TBD — will iterate once we see what metrics OpenClaw exposes). Docker-in-Docker sidecar (future enhancement, not needed for initial deploy).

### Task 13: Verify Prometheus scraping

- [ ] **Step 1: Check ServiceMonitor is picked up**

```bash
kubectl get servicemonitor -n openclaw
```

Expected: `openclaw` ServiceMonitor exists.

- [ ] **Step 2: Verify Prometheus is scraping**

Port-forward to Prometheus (use the monitoring justfile) and check that the `openclaw` target appears in Status → Targets.

If the ServiceMonitor isn't being picked up, it may need a label that matches the Prometheus operator's `serviceMonitorSelector`. Check:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector
```

And add matching labels to the ServiceMonitor if needed.

- [ ] **Step 3: Explore available metrics**

In the Prometheus UI, search for metrics prefixed with `openclaw_` to see what's available natively.

- [ ] **Step 4: Commit any ServiceMonitor label fixes**

```bash
git add k8s/openclaw/base/servicemonitor.yaml
git commit -m "fix(openclaw): align ServiceMonitor labels with Prometheus selector"
```

### Task 14: Add Slack cost visibility

- [ ] **Step 1: Test cost query via system prompt**

In Slack, ask: `@dopeclaw how much have we spent on OpenRouter?`

If dopeclaw can already hit the OpenRouter API (it has the key as an env var and can execute code), it should be able to query spend. If not, we may need a custom OpenClaw skill.

- [ ] **Step 2: If needed, create a cost-check skill**

This depends on what OpenClaw supports natively. If the system prompt approach works, skip this step. If not, create a custom skill that queries the OpenRouter `/api/v1/auth/key` endpoint.

- [ ] **Step 3: Document what works**

Update the spec or add a note in the justfile about how cost visibility works in practice.
