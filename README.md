# Home Automation Kubernetes Configuration

This repository contains Kubernetes configurations for deploying home automation applications using FluxCD. Currently includes:

- OpenHAB - Home automation platform
- Mosquitto - MQTT message broker

## Prerequisites

- Kubernetes cluster (K3s)
- FluxCD installed
- GitHub repository access

## Installation

1. Install Flux CLI:
```bash
brew install fluxcd/tap/flux
```

2. Check your cluster is ready:
```bash
flux check --pre
```

3. Bootstrap Flux with your GitHub repository:
```bash
flux bootstrap github \
  --owner=jannegpriv \
  --repository=k3s-cluster-config \
  --branch=main \
  --path=clusters/production \
  --personal
```

4. Add the Jetstack Helm repository for cert-manager:
```bash
flux create source helm jetstack \
  --url=https://charts.jetstack.io \
  --namespace=flux-system
```

## Repository Structure

```
clusters/
└── production/
    ├── cert-manager/
    │   ├── cluster-issuer.yaml
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   └── release.yaml
    ├── openhab/
    │   ├── kustomization.yaml
    ├── mosquitto/
    │   ├── mosquitto-claims.yaml
    │   ├── mosquitto-service.yaml
    │   ├── mosquitto-statefulset.yaml
    │   └── kustomization.yaml
    │   ├── openhab-claims.yaml
    │   ├── openhab-service.yaml
    │   ├── openhab-statefulset.yaml
    │   └── openhab-traefik.yaml
    └── flux-system/
        └── kustomization.yaml
```

## Verification

1. Check Flux is syncing:
```bash
flux get kustomizations
```

2. Check cert-manager installation:
```bash
flux get helmreleases -n cert-manager
```

3. Check OpenHAB deployment:
```bash
kubectl get pods
kubectl get ingress
```

## Architecture

### Network Flow

```mermaid
graph TD
    A[External Client] -->|HTTPS| B[Cloudflare Edge]
    B -->|Cloudflare Tunnel| C[cloudflared Pod]
    C -->|HTTPS| D[Traefik Ingress]
    D -->|HTTPS/HTTP| E[OpenHAB Service]
    F[Local Client] -->|Direct HTTPS/HTTP| D
```

### Component Details

1. **Cloudflare Edge**
   - Handles external TLS termination
   - Provides DDoS protection
   - Manages DNS for openhab.k3s.nu

2. **Cloudflare Tunnel**
   - Runs as a Pod in the `cloudflare` namespace
   - Creates secure outbound connection to Cloudflare
   - No need for public IP or open ports
   - Routes traffic to Traefik using internal service discovery

3. **Traefik Ingress**
   - Handles both external (via Cloudflare) and local traffic
   - Configured using IngressRoute CRDs
   - Manages TLS for direct access
   - Uses middleware for security and routing

### Traefik Components

```mermaid
graph TD
    A[IngressRoute] -->|references| B[Middleware]
    A -->|routes to| C[Service]
    B -->|types| D[Headers]
    B -->|types| E[Redirects]
    B -->|types| F[SSL]
    D -->|configures| G[Security Headers]
    E -->|manages| H[HTTP to HTTPS]
    F -->|enforces| I[TLS Settings]
```

### Middleware Explanation

Traefik middleware acts as a series of steps that process requests before they reach your service:

1. **Security Headers Middleware** (`openhab-https`)
   ```yaml
   # Sets critical security headers
   - sslRedirect: true           # Force HTTPS
   - forceSTSHeader: true        # Use Strict Transport Security
   - stsSeconds: 31536000        # HSTS for 1 year
   - stsIncludeSubdomains: true  # Apply to subdomains
   - stsPreload: true            # Allow preloading in browsers
   ```

2. **Protocol Headers**
   - Sets `X-Forwarded-Proto: "https"` to ensure applications know the original protocol

The middleware chain ensures that:
- All traffic is secure
- Security policies are enforced consistently
- Headers are properly set for proxied connections

## Access

OpenHAB can be accessed in two ways:

1. **External Access**: https://openhab.k3s.nu
   - Routes through Cloudflare
   - Full SSL/TLS encryption
   - DDoS protection

2. **Local Access**: http://openhab.k3s.nu
   - Direct access within local network
   - Bypasses Cloudflare
   - Optional HTTPS available

## FluxCD Architecture

### Overview

```mermaid
graph TD
    A[GitHub Repository] -->|Poll Changes| B[Source Controller]
    B -->|Fetch| C[Kustomize Controller]
    B -->|Fetch| D[Helm Controller]
    C -->|Apply| E[Kubernetes API]
    D -->|Apply| E
    F[Notification Controller] -->|Alert| G[Notifications]
```

### Components

1. **Source Controller**
   - Monitors Git repositories and Helm repositories
   - Downloads artifacts and verifies checksums
   - Makes artifacts available to other controllers
   - Your sources:
     - Git: `jannegpriv/k3s-cluster-config`
     - Helm: cert-manager, weave-gitops

2. **Kustomize Controller**
   - Watches for `Kustomization` resources
   - Builds and applies kustomizations
   - Prunes resources that are no longer needed
   - Your kustomizations:
     - `/clusters/production/apps`
     - `/clusters/production/infrastructure`

3. **Helm Controller**
   - Manages Helm chart releases
   - Automatically upgrades releases
   - Your releases:
     - cert-manager
     - weave-gitops

4. **Notification Controller**
   - Handles alerts and notifications
   - Can notify about reconciliation failures

## Mosquitto MQTT Broker

The Mosquitto MQTT broker is deployed as a StatefulSet with persistent storage using Rook/Ceph. It provides:

- MQTT protocol support on port 1883
- Persistent message storage
- Direct access through the master node's IP (192.168.50.75:1883)
- Resource limits to ensure stable operation

The deployment consists of:
- StatefulSet with 1 replica
- Persistent storage for configuration, data, and logs
- Service configuration for internal and external access

### Directory Structure Explained

```
clusters/production/
├── apps/                    # Application workloads
│   └── openhab/            # OpenHAB configuration
│       ├── kustomization.yaml     # Resource composition
│       ├── openhab-claims.yaml    # PVC definitions
│       ├── openhab-service.yaml   # Service definition
│       ├── openhab-traefik.yaml   # Ingress configuration
│       └── openhab-statefulset.yaml # Main deployment
├── infrastructure/          # Infrastructure components
│   ├── cert-manager/       # Certificate management
│   ├── cloudflare/         # Cloudflare tunnel
│   └── weave-gitops/       # GitOps UI
└── flux-system/            # Flux core components
```

### GitOps Workflow

1. **Change Process**:
   ```mermaid
   sequenceDiagram
       participant Dev as Developer
       participant Git as GitHub
       participant Flux as FluxCD
       participant K8s as Kubernetes
       
       Dev->>Git: Push changes
       Flux->>Git: Poll for changes
       Flux->>Flux: Validate changes
       Flux->>K8s: Apply changes
       K8s-->>Flux: Report status
       Flux-->>Git: Update status
   ```

2. **Reconciliation**:
   - Flux checks your Git repository every 1 minute
   - Changes are automatically applied
   - Failed changes are reported and retried

### Weave GitOps UI

Access the UI locally at http://weave.local

Make sure your local DNS (e.g., `/etc/hosts`) has an entry for `weave.local` pointing to your K3s cluster IP.

Credentials:
- Username: admin
- Default password: flux (should be changed)

Features:
- Visual cluster overview
- Resource status and health
- Reconciliation logs
- Helm release management

## Secrets Management

This repository uses plain Kubernetes secrets for simplicity. Before deploying, you need to:

1. Update the Cloudflare API token in `clusters/production/infrastructure/cert-manager/cloudflare-secret.yaml`
   ```yaml
   stringData:
       api-token: your-cloudflare-api-token-here
   ```

2. Apply the secret:
   ```bash
   kubectl apply -f clusters/production/infrastructure/cert-manager/cloudflare-secret.yaml
   ```

**Note:** Since this is not a production system, we're using plain Kubernetes secrets committed to the repository. In a production environment, you should use a proper secrets management solution like SOPS, Sealed Secrets, or Vault.

## Troubleshooting

1. Check Flux logs:
```bash
flux logs
```

2. Check cert-manager status:
```bash
kubectl get certificates,certificaterequests
```

3. Check OpenHAB pods:
```bash
kubectl describe pod -l app=openhab-production
```
