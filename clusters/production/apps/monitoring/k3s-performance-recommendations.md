# K3s Performance Recommendations

## Current Issues

- API server high latency (>15s for WATCH requests)
- High memory usage on master node (67%)
- Resource-intensive applications competing for limited resources on Raspberry Pi hardware

## Recommended Actions

### 1. Optimize Prometheus Resource Usage

```yaml
# Add to your prometheus values in kube-prometheus-stack helm release
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 50m
        memory: 512Mi
      limits:
        cpu: 200m
        memory: 1Gi
    retention: 5d  # Reduce from default 10d
    retentionSize: "10GB"
    scrapeInterval: "60s"  # Increase from default 30s
    evaluationInterval: "60s"  # Increase from default 30s
```

### 2. Optimize Kubeshark Resource Usage

```yaml
# Add to your kubeshark values
resources:
  worker:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 100m
      memory: 256Mi
  hub:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

### 3. Tune K3s for Better Performance

Edit `/etc/systemd/system/k3s.service` on the master node:

```
[Service]
...
ExecStart=/usr/local/bin/k3s server \
  --kube-apiserver-arg="max-requests-inflight=400" \
  --kube-apiserver-arg="max-mutating-requests-inflight=200" \
  --kube-apiserver-arg="request-timeout=300s" \
  --kube-controller-manager-arg="node-monitor-period=5s" \
  --kube-controller-manager-arg="node-monitor-grace-period=20s" \
  ...
```

### 4. Increase etcd Performance

```
# Add to k3s config
--etcd-arg="heartbeat-interval=100" \
--etcd-arg="election-timeout=1000" \
--etcd-arg="snapshot-count=10000"
```

### 5. Consider Hardware Upgrades

- Add more RAM to the master node if possible
- Use SSD storage for the master node to improve etcd performance
- Consider dedicating the master node solely to control plane components

### 6. Reduce Node Pressure

- Move resource-intensive workloads to worker nodes
- Use node affinity to keep Prometheus, Rook-Ceph, and other intensive workloads off the master node

## Implementation Priority

1. Optimize Prometheus and Kubeshark resource usage (immediate)
2. Tune K3s API server parameters (requires restart)
3. Add node affinity rules to move workloads off the master node
4. Consider hardware upgrades if issues persist
