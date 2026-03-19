# Dopeclaw — OpenClaw Deployment on K3s

**Date:** 2026-03-18
**Status:** Draft
**Branch:** `collin/openclaw`

## Overview

Deploy an OpenClaw AI agent ("dopeclaw") to the existing K3s cluster, integrated with the dopetraxx Slack workspace (~20 users). The bot responds to `@dopeclaw` mentions, can build projects, do research, execute code, and browse the web — all from a sandboxed, persistent workspace.

The goal is to make dopeclaw genuinely fun and useful for the group while keeping it isolated from personal accounts and easy to operate.

## Architecture Decision

**Kustomize-native deployment** with base manifests and per-environment overlays (staging/production). This matches both OpenClaw's official K8s deployment pattern and the existing conventions in this repo (atuin, blog use the same approach). The reusable webapp Helm chart was considered but rejected — OpenClaw is an outbound agent process, not an HTTP-serving web app.

## Directory Structure

```
k8s/openclaw/
├── .justfile
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── pvc.yaml
│   ├── service.yaml              # metrics-only (port 18789 for Prometheus)
│   ├── servicemonitor.yaml       # Prometheus scrape config
│   ├── configmap.yaml
│   └── system-prompt.yaml
```

Single deployment — no staging/production overlays. A staging environment would require a separate Slack app (Socket Mode round-robins events between connected clients). The blast radius is low enough that `just update-prompt` is sufficient for iterating.

## Components

### Container & Runtime

- Official OpenClaw container image
- Non-root user (UID 1000), all capabilities dropped
- mise available for installing per-project tooling (Python, Node, Go, Rust, etc.)
- Single replica — this is a stateful agent, not a horizontally scalable service

### Storage (PVC)

- **Size:** 10Gi
- **Contents:** OpenClaw agent state, memory, workspace projects
- Single PVC mounted at `/data`
- `/data/workspace` — project files (symlinked or configured as OpenClaw's workspace path)
- `/data/openclaw` — agent state/memory (configured as `OPENCLAW_HOME` or symlinked from `~/.openclaw`)
- Both persist across pod restarts
- Using a single mount point with subdirectories keeps the manifest simple — no subPath gymnastics

### Resource Allocation

| Resource | Request | Limit |
|----------|---------|-------|
| Memory   | 512Mi   | 1Gi   |
| CPU      | 250m    | 1000m |

Cluster is underutilized, so these are liberal. OpenClaw + Chromium (for web browsing) can be memory-hungry.

### LLM Provider

- **Provider:** OpenRouter (single API key, access to all major models)
- **Default model:** `anthropic/claude-sonnet-4`
- **Switching models:** Change the model string in the ConfigMap, no code changes
- **Billing:** OpenRouter account, friends can contribute funds to cover API costs
- API key stored in `openclaw-secrets` Kubernetes Secret

### Slack Integration

- **Mode:** Socket Mode (persistent WebSocket — no public URL or ingress required)
- **Bot name:** `dopeclaw`
- **Mention-gated:** Responds to `@dopeclaw` mentions and DMs
- **Credentials:** App Token (`xapp-...`) and Bot Token (`xoxb-...`) stored in `openclaw-secrets`

**Required Slack bot scopes:**
- `chat:write` — send messages
- `channels:history` — read channel messages
- `im:history` — read DMs
- `app_mentions:read` — detect @mentions
- `reactions:write` — react to messages
- `files:write` — upload files

**Required event subscriptions:**
- `app_mention`
- `message.channels`
- `message.im`

**Slack app creation is a manual prerequisite** — the spec includes a step-by-step walkthrough.

### Configuration (ConfigMaps)

**openclaw-config** — main OpenClaw configuration:
```yaml
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

**openclaw-system-prompt** — personality and behavior (separate ConfigMap, mounted as a file volume for easy iteration):
- Ray Porter-esque personality: warm, dry, competent, unbothered
- Aware it's in a group Slack called dopetraxx
- Knows it can use mise to install tools for projects
- Knows its workspace persists across conversations
- Instructed to never access personal accounts — suggests creating dedicated accounts when auth is needed
- Mounted as a volume (not env var) so the `update-prompt` justfile recipe can re-apply the ConfigMap and restart the pod to pick up changes

### Secrets

Created via `.justfile` recipe from env vars (sourced from `.envrc` via direnv):

| Secret Key           | Source                    |
|----------------------|---------------------------|
| `OPENROUTER_API_KEY` | OpenRouter dashboard       |
| `SLACK_BOT_TOKEN`    | Slack app config (`xoxb-`) |
| `SLACK_APP_TOKEN`    | Slack app config (`xapp-`) |

All stored in a single `openclaw-secrets` Kubernetes Secret in the `openclaw` namespace.

## Justfile Recipes

```
create-namespace        # kubectl create namespace openclaw
create-secrets          # create openclaw-secrets from env vars
deploy [env]            # kubectl apply -k overlays/{env} (default: production)
delete [env]            # kubectl delete -k overlays/{env}
status                  # pod/svc/pvc status
logs                    # follow pod logs
restart                 # rolling restart
get-all                 # all resources in namespace
describe                # describe the deployment
update-prompt           # re-apply system-prompt configmap + restart pod
```

## Observability

### Logging

OpenClaw logs to stdout. Loki picks them up automatically via the existing collection stack. No additional configuration needed.

### Metrics & Cost Tracking

- OpenClaw gateway exposes metrics on port 18789
- ServiceMonitor added so Prometheus scrapes the metrics endpoint
- If native token/cost metrics are insufficient, a lightweight cron skill or sidecar polls the OpenRouter `/api/v1/auth/key` endpoint and exposes spend data as Prometheus metrics

### Grafana Dashboard

A dedicated dashboard showing:
- Token usage over time
- Cost by model
- Request count
- Error rate

Dashboard layout is TBD — will iterate after initial deploy once we see what metrics OpenClaw actually exposes. Deployed as a ConfigMap in the monitoring namespace once finalized.

### Slack Cost Visibility

Dopeclaw responds to natural language cost queries ("how much have we spent?") by hitting the OpenRouter API and reporting back in Slack. Configured via system prompt or a custom OpenClaw skill.

## Security Boundaries

### What dopeclaw CAN do:
- Read/write files in its PVC workspace
- Execute code in its sandbox (Python, JS, shell)
- Browse the web via built-in Chromium
- Install tools via mise into its workspace
- Communicate via Slack (dopetraxx workspace only)
- Make API calls to OpenRouter

### What dopeclaw CANNOT do:
- Access other K8s namespaces or cluster resources
- Read/write anything outside its PVC
- Access personal accounts (enforced by prompt + no credentials)
- Escape its container sandbox
- Use host networking or privileged operations

### Future: Docker-in-Docker

If container building is needed later, add a Docker-in-Docker sidecar with isolated storage. This keeps container operations sandboxed — dopeclaw cannot interfere with other workloads on the cluster. Not included in the initial deployment.

## Prerequisites (Manual Steps)

1. **Create OpenRouter account** at openrouter.ai — generate an API key, add initial credits
2. **Create Slack app** at api.slack.com for the dopetraxx workspace — detailed walkthrough provided during implementation
3. **Add env vars** to `.envrc`: `OPENROUTER_API_KEY`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`

## Open Questions

- Exact OpenClaw container image tag / version pinning strategy
- Whether mise should be baked into a custom image or bootstrapped at runtime
- Specific Grafana dashboard layout (can iterate after initial deploy)
- Whether to add Prometheus alerts for spend thresholds
