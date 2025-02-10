# OpenHAB Kubernetes Configuration

This repository contains Kubernetes configurations for deploying OpenHAB using FluxCD.

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
  --repository=openhab-k8s \
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

## Access

Once deployed, OpenHAB will be available at: https://openhab.k3s.nu

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
