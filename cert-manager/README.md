# Cert-Manager Setup

This directory contains the configuration for cert-manager, which handles SSL/TLS certificates for the OpenHAB deployment.

## Installation

1. Install cert-manager using Helm:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true
```

2. Update the email address in `cluster-issuer.yaml`

3. Apply the ClusterIssuer:

```bash
kubectl apply -f cluster-issuer.yaml
```

## Configuration

The `cluster-issuer.yaml` file defines a ClusterIssuer that uses Let's Encrypt to obtain SSL certificates. It's configured to:

- Use the production Let's Encrypt server
- Use HTTP01 challenge type
- Work with Traefik ingress
- Create certificates that will be automatically renewed before expiry

## Verification

To verify the installation and configuration:

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check ClusterIssuer status
kubectl get clusterissuer letsencrypt-prod -o wide

# Once OpenHAB is deployed, check certificate status
kubectl get certificate -n default
```

## Troubleshooting

If certificates are not being issued:

1. Check cert-manager logs:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

2. Check certificate request status:
   ```bash
   kubectl get certificaterequest
   ```

3. Verify the Ingress is properly annotated:
   ```bash
   kubectl get ingress openhab-production -o yaml
   ```
