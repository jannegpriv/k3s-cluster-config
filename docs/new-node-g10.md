# k3s-w-6: GMKtec G10

Installation date: 2026-09-28. This runbook covers the first AMD64 worker in
the existing ARM64 cluster. Ceph deployment and openHAB migration are separate steps.

## Identity and installed OS

- GMKtec G10 / BIOS identifies NucBox G10 Pro, Ryzen 5 3500U, 16 GB DDR4.
- Hostname `k3s-w-6`, user `janne`, machine-id `17718bedd82a4409b195c2d98045e3de`.
- Ubuntu Server 24.04.5 LTS, `linux-generic-hwe-24.04`, running `7.0.0-34-generic`.
- Use the HWE installer: kernel 6.8 did not support this RTL8125 revision (XID 689).
- Ethernet `eno1`, MAC `84:47:09:8e:db:29`, address `192.168.50.168/24`.
  Janne confirmed saving this DHCP reservation in the ASUS router on 2026-09-28;
  SSH and the address were checked afterwards. The reservation has not been read
  back directly from the router.
- SSH uses Janne's existing public key; password authentication is disabled.
  Sudo credentials are stored only in the protected local secrets directory.
- Swap is disabled. BIOS UMA framebuffer is `512M`, giving Linux about 15.1 GiB.
- BIOS `Auto Power On` is `Power On`; recovery after an actual power outage has
  not been tested. Power Limit remains `Balance`.

## Disk layout

The internal SSD was erased with Janne's explicit approval.

| Device | Size | Use |
| --- | --- | --- |
| `/dev/nvme0n1p1` | 200 GiB | ext4 root filesystem |
| `/dev/nvme0n1p2` | 1,127,219,200 bytes | FAT32 EFI boot |
| `/dev/nvme0n1p3` | 808,331,509,760 bytes | Raw partition reserved for Ceph |

SSD: TWSC TSC3AN1T0-F6Q10S, serial `TTSQA25APX20917`.
Do not format or mount partition 3 as a normal filesystem.

## Joining the cluster

1. Reconcile Mattermost's mandatory `kubernetes.io/arch: arm64` selector first.
   The custom image `ghcr.io/jannegpriv/mattermost-arm64:11.7.6` was checked in
   the registry and has only a Linux ARM64 manifest. This template change causes
   a brief restart because the deployment uses `Recreate` with an RWO volume.
2. Check all existing nodes are Ready and Ceph reports `HEALTH_OK`.
3. Copy `nodes/k3s-w-6/config.yaml` to `/etc/rancher/k3s/config.yaml` on the verified
   machine. Store the join token separately in `/etc/rancher/k3s/agent-token`,
   owned by root with mode 0600. Never commit or print the token.
4. Install the official K3s agent with `INSTALL_K3S_VERSION=v1.34.3+k3s1`, matching
   the control plane. This is an agent, not another control plane.
5. The initial `onboarding.k3s.nu/pending=true:NoSchedule` taint blocks ordinary
   workloads during validation. DaemonSets with broad tolerations may still run.
6. Verify Ready, architecture, memory, metrics and cross-node pod networking/DNS.
   Review storage discovery before enabling ordinary scheduling.
7. Once these checks pass, remove the onboarding taint both from this config and
   from the live Node. K3s applies `node-taint` only at initial registration.

## Verified after join, 2026-09-28

- `k3s-agent` is enabled and active. Kubernetes reports `Ready`, architecture
  `amd64`, 8 logical CPUs and 15,792,572 KiB memory (about 15.1 GiB).
- Pod CIDR is `10.42.2.0/24`. A Job on w-6 resolved the Kubernetes service through
  cluster DNS and received a healthy HTTP response from Mattermost on w-3.
  Its first attempt timed out on DNS during initial networking setup; its retry
  completed. The test was deployed and pruned through Flux; its manifest is kept
  in `nodes/k3s-w-6/network-check.yaml` for reference, outside the active app tree.
- `kubectl top node k3s-w-6` returned CPU and memory samples; node-exporter is Ready.
- All six nodes are Ready. All five existing OSDs are Ready and Ceph is `HEALTH_OK`.
- Mattermost's ARM64 selector is reconciled and its replacement pod is Ready on w-3.
- Systemd reports `running`, with no failed services. Sleep, suspend, hibernate
  and hybrid-sleep targets are masked; swap remains disabled.
- `/dev/nvme0n1p3` is still raw/unmounted. No new Ceph OSD has been created.
- **The onboarding NoSchedule taint remains.** Rook currently has `useAllNodes`
  and `useAllDevices` enabled, which can automatically consume raw partitions.
  Configure the intended device explicitly and review the storage rollout before
  removing the taint. Only explicitly tolerating workloads run here for now.
- Do not set `node-role.kubernetes.io/worker` through kubelet `node-label`:
  Kubernetes 1.34 rejects this reserved label. An agent still acts as a worker
  without the cosmetic role label (`kubectl get nodes` displays `<none>`).

## Follow-up work

- Add the raw Ceph partition explicitly via GitOps, preserving Ceph 18.2.2,
  replication size 3 and the current OSD memory limits. Verify health and rebalance.
- Migrate openHAB in a separate controlled step, retaining its 4 GiB memory limit.
- Do not upgrade Ceph or change the existing ARM workers as part of this join.

## Ceph rollout, 2026-09-28

Janne approved adding the reserved partition and then enabling ordinary scheduling.
The initial change explicitly selects `/dev/nvme0n1p3` on w-6 and lets only OSD
preparation and OSD pods tolerate the onboarding taint. Existing OSD placements
receive this same narrow toleration; Rook manages their rollout.

Preflight verified the machine-id and SSD serial above, the exact partition size,
no filesystem signatures or mounts on p3, and no existing LVM physical volumes.
All five existing OSDs were up/in, Ceph reported `HEALTH_OK`, and `replicapool`
used size 3, min_size 2 and the `replicapool_host` CRUSH rule (host failure domain).
Existing CRUSH weights and reweights are preserved; the new OSD uses its normal
capacity-derived weight. Ceph/Rook versions and recovery limits remain unchanged.

Keep the node taint until six OSDs are up/in and rebalance completes with healthy
PGs. Then sync the final node config, remove the live onboarding taint, and verify
the AMD64 storage drivers before moving applications. openHAB remains on w-5.

## References

- https://docs.k3s.io/quick-start
- https://docs.k3s.io/cli/agent
- https://docs.k3s.io/installation/requirements
- https://rook.io/docs/rook/v1.14/CRDs/Cluster/ceph-cluster-crd/
