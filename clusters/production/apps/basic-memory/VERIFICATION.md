# Pilot acceptance — 2026-09-19

Initial installation: [PR #2](https://github.com/jannegpriv/k3s-cluster-config/pull/2),
merged revision `7b35e6cdc651a588690df670e8b826c1e01fb30b`.

| Check | Observed result |
| --- | --- |
| GitOps | Flux `apps` Ready at the merged revision; server-side dry-run and Kustomize rendering passed. |
| Runtime | Pinned Basic Memory 0.23.2 on ARM64, one ready replica; initial idle memory approximately 206 MiB. |
| Storage | 5 GiB Ceph RBD PVC Bound, production PV Retain; namespace/PVC protected from Flux pruning. |
| HTTPS and auth | Trusted certificate for `memory.k3s.nu`; missing and incorrect credentials both returned 401. |
| MCP clients | 21 tools discovered. The Codex Keychain header helper and independent `agent` credential both initialized successfully. Cross-client Swedish create/read/search/update/delete passed using `scripts/mcp-client.py`. |
| Public access | Independent GitHub runner had working Internet access, found no public address for the name, and could not connect to WAN IPv4 82.183.35.198 with the correct TLS SNI/Host, including a forged forwarded header. [Live boundary check](https://github.com/jannegpriv/k3s-cluster-config/actions/runs/35466362513). |
| Pod isolation | A default-namespace test pod could reach Traefik but was refused connection to the MCP Service. A request executed from Traefik reached the backend and received an HTTP response. |
| Restart and relocation | Deleting the app pod rescheduled it from `k3s-w-1` to `k3s-w-4`; the same test note remained readable over authenticated MCP. |
| NAS backup | A manual Job from the CronJob completed in 17s; pinned SSH host key, archive contents, and remote/downloaded SHA256 were verified. |
| Restore | Restored the NAS archive to a separate Ceph PVC in an isolated namespace. Confirmed that SQLite did not exist before startup, then rebuilt it and verified identical Markdown hashes plus Swedish MCP read/search. Temporary restore resources were removed. |
| Monitoring | All three Prometheus rules loaded with health `ok`; availability, CronJob creation time, and PVC-capacity metrics were present. |
| Initial content | Seven notes from the user's explicitly approved goals and pilot decisions were written and read back with the other credential. Synthetic CRUD/persistence notes were removed. No personal files were bulk-imported. |
| Search timing | 21 text queries over seven notes: median 0.912s, p95 0.962s. Includes a fresh HTTPS connection and Tailscale round trip per request; excludes model inference. This is a small-pilot measurement. |

The first tested NAS archive was `basic-memory-20260919T200414284520Z.tar.gz`,
SHA256 `91b77d58c0ba08eeea94a6632c5f47bf3cae1c7a85df11b70bf994996661d501`.
It contained a synthetic persistence note and configuration; production notes are
covered by subsequent backups. Scheduled backups run at 03:30 Europe/Stockholm;
manual Jobs do not update the CronJob's last-successful timestamp.

## Local client handoff

Remote.it SSH configuration was archived and its Include removed. Direct
`ssh janne@k3s-m-1` now works through the existing Tailscale subnet route.

Both credentials are in the Mac login Keychain. The Codex config and header helper
were parsed/executed successfully without printing credentials. An administrator
must still add `192.168.50.75 memory.k3s.nu` to the Mac's `/etc/hosts`; unattended
sudo requires a password. Acceptance requests used a connection-IP override while
preserving the real Host, SNI and certificate verification. A new interactive
Codex task can use the configured MCP server after name resolution is installed.
