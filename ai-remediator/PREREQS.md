# AI Remediator — Prerequisites (Phase 0)

Verified 2026-07-10.

| Item | Status | Value |
|---|---|---|
| n8n version | ✅ | 2.29.9 (AI Agent/Tools Agent, Call n8n Workflow Tool, Wait node with webhook resume — all present) |
| Anthropic API credential | ✅ | n8n credential `Anthropic account` (type `anthropicApi`) — reused by existing flows |
| Agent runtime model | ✅ | `claude-sonnet-5` (intro pricing until 2026-08-31) |
| Mattermost integration | ✅ | Existing incoming webhooks reused: `k3s-alerts` (raw feed, untouched), `k3s-cluster` (agent reports + approval requests) |
| Alertmanager | ✅ | kube-prometheus-stack; receivers configured via HelmRelease values (`clusters/production/apps/monitoring/helm-release.yaml`); existing n8n webhook receiver stays, new `ai-remediator` route added with `continue: true` |
| Network path n8n → K8s API | ✅ | n8n runs in-cluster; `https://kubernetes.default.svc` (pattern already used by the K3s status workflow) |
| K8s auth for agent | Phase 1 | Dedicated ServiceAccount `ai-remediator` (namespace `automation`), token as a NEW n8n Header Auth credential — never the admin kubeconfig |

## Namespace scope (decided by Janne 2026-07-10)

Write tools allowed in (`REMEDIATOR_NAMESPACES`):

```
openhab, mattermost, n8n, mosquitto, uptime-kuma, bitwarden, headlamp,
authelia, loki, monitoring, remediator-test
```

Always excluded (no RoleBinding = no access): `kube-system`, `rook-ceph`,
`flux-system`, `cert-manager`, `cloudflare`, `default`, `kube-public`,
`kube-node-lease`.

Note on `monitoring`: the agent can remediate its own alert chain
(Prometheus/Alertmanager/Grafana) — accepted circular risk; rate limit +
cooldown (Phase 5) bound the blast radius.

## Config summary (target values)

| Var | Value |
|---|---|
| `REMEDIATOR_ENABLED` | `true` (kill switch) |
| `REMEDIATOR_NAMESPACES` | list above |
| `MAX_REPLICAS` | 3 (Pi cluster — keep low) |
| `COOLDOWN_MINUTES` | 30 |
| `MAX_ACTIONS_PER_HOUR` | 4 |
| Approval timeout | 15 min, timeout = deny |
