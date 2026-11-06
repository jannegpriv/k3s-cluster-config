# Basic Memory verification

## Hybrid activation — 2026-11-06

Implemented in [PR #6](https://github.com/jannegpriv/k3s-cluster-config/pull/6),
merged revision `a892f47a278cac1b2a9357d02f530307d8b09e42`.

- The pinned runtime accepted the FastEmbed multilingual MiniLM model, 384
  dimensions, persistent model cache, and `default_search_type=hybrid`.
  `sqlite-vec` loaded successfully. No embedding API credentials are used.
- Five backup tests, Kustomize rendering, server-side deployment dry run, GitHub
  validation, the independent public-boundary check, and the repository review
  workflow passed.
- Flux applied the merged revision. The replacement pod became Ready on
  `k3s-w-6`; the retained Ceph volume moved successfully from `k3s-w-4`.
- `basic-memory reindex --embeddings -p main` completed with 58 entities embedded,
  zero skipped, and zero errors. Final database readback found all 59 notes
  represented by 3,523 ready chunks and 3,523 vectors.
- Production MCP searches succeeded in `text`, `vector`, explicit `hybrid`, and
  default modes. A Swedish operational query returned the expected existing note
  first in vector, hybrid, and default modes; default and explicit hybrid results
  matched. Note titles and private contents are intentionally omitted here.
- Aggregate path/content SHA256 for all Markdown notes matched before and after
  activation. There were zero pending file writes and zero pod restarts at the
  final check. Resource monitoring stayed below the 2 GiB container limit.
- Manual NAS backups both before and after activation completed and verified
  their remote SHA256 checksums. The post-activation backup ran with the app's
  volume on the new node. The existing nightly schedule and retention remain.
- Model files are cached under `/data/cache/fastembed`; derived SQLite vectors
  and model artifacts remain excluded from the file backup. Recovery rebuilds
  vectors using the configured model, as described in README.md.

The checks above verify activation and a bounded live search sample, not a
general retrieval-quality benchmark or a new full restore drill.

## Initial pilot — 2026-09-19

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
It contained a synthetic persistence note and configuration. After the seven
approved notes were added, `basic-memory-20260919T201352832176Z.tar.gz` completed in
13s and its eight files were downloaded and verified against the archive manifest.
Its SHA256 is `daa8cf15fe792f7f1a90f76c458dce29b726ed7b4222ed3e0ff205138d02d15d`.
Scheduled backups run at 03:30 Europe/Stockholm;
manual Jobs do not update the CronJob's last-successful timestamp.

## Local client handoff

Remote.it SSH configuration was archived and its Include removed. Direct
`ssh janne@k3s-m-1` now works through the existing Tailscale subnet route.

Both credentials are in the Mac login Keychain. The Codex config and header helper
were parsed/executed successfully without printing credentials. The desktop app's
bundled Codex 0.155.0-alpha.9.2 recognizes the header helper, and `basic_memory` is
enabled. The separately installed CLI 0.146.0 lacks this feature; it was not upgraded.

After macOS administrator authorization, `192.168.50.75 memory.k3s.nu` was added to
`/etc/hosts`, with backup `/etc/hosts.before-basic-memory-20260919-231552`.
System DNS resolved the private address, and both accounts initialized MCP and
discovered 21 tools **without** a connection-IP override. Unauthenticated ordinary
HTTPS returned 401. A new desktop Codex task can load the configured memory server.
