# K3s Tuning Guide for Raspberry Pi Clusters

This guide provides instructions for tuning your K3s cluster to improve API server performance and reduce latency alerts.

## Step 1: Create or Edit K3s Config File

On your master node (k3s-m-1), create or edit the K3s config file:

```bash
sudo nano /etc/rancher/k3s/config.yaml
```

Add the following configuration:

```yaml
# API Server tuning
kube-apiserver-arg:
  - "max-requests-inflight=400"
  - "max-mutating-requests-inflight=200"
  - "request-timeout=300s"
  - "default-watch-cache-size=200"
  - "watch-cache-sizes=pods#500,nodes#0,persistentvolumeclaims#50"

# Controller Manager tuning
kube-controller-manager-arg:
  - "node-monitor-period=5s"
  - "node-monitor-grace-period=20s"
  - "pod-eviction-timeout=300s"

# Etcd tuning
etcd-arg:
  - "heartbeat-interval=100"
  - "election-timeout=1000"
  - "snapshot-count=10000"

# General K3s settings
write-kubeconfig-mode: "0644"
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cluster-dns: "10.43.0.10"
```

## Step 2: Restart K3s Service

After making changes to the config file, restart the K3s service:

```bash
sudo systemctl restart k3s
```

## Step 3: Monitor Performance

Monitor the API server performance after applying these changes:

```bash
# Check API server latency
kubectl get --raw /metrics | grep apiserver_request_duration_seconds

# Check etcd performance
kubectl get --raw /metrics | grep etcd_request_duration_seconds
```

## Step 4: Additional System Tuning

For Raspberry Pi nodes, consider these additional system optimizations:

### Memory Management

Add to `/etc/sysctl.conf`:

```
# Increase memory available for network operations
net.core.rmem_max=8388608
net.core.wmem_max=8388608

# Improve memory management
vm.swappiness=10
vm.vfs_cache_pressure=50
```

Apply changes:

```bash
sudo sysctl -p
```

### File System Tuning

If using SD cards, reduce write wear:

```bash
# Add to /etc/fstab
tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,size=100m 0 0
```

## Step 5: Hardware Recommendations

For optimal performance:

1. Use high-quality SD cards (Class 10 or better) or preferably USB SSDs
2. Ensure adequate cooling for all Raspberry Pi nodes
3. Consider adding a dedicated master node with more RAM
4. Use a powered USB hub if connecting multiple peripherals
