# Basic Memory pilot

One replica of the pinned Basic Memory 1.0.0 image, Markdown in `/data/memory`, configuration
and rebuildable SQLite index in `/data/config`, on the retained 5 GiB Ceph RBD PVC.
The Deployment uses Recreate; brief update interruptions are expected. Hybrid search
uses local FastEmbed inference; no external model API or telemetry is enabled.
App pods have no Kubernetes token.

## SQLite compatibility overlay

The official 1.0.0 local project indexer hardcodes eight concurrent database tasks,
including search refreshes. On this corpus, full indexing failed on 13 files even
with the MCP server stopped. Running the same index with one task completed all
59 files and reconstructed every authored relation.

`scripts/sqlite-index-compat.py` changes only the two local batch-concurrency
defaults from eight to one. An unprivileged init container checks the exact
upstream module SHA256 and builds a read-only module overlay in an emptyDir.
Both the server and maintenance CLI use it. Reads and embedding settings stay
unchanged. This is a local compatibility fix on the pinned upstream 1.0.0 image;
it must be reviewed or removed at the next image upgrade. A different source hash
refuses startup. Recovery Jobs must mount this same overlay, as the validation
renderer does; a bare upstream image will reproduce the failure.

Earlier reports [#1322](https://github.com/basicmachines-co/basic-memory/issues/1322)
and [#1581](https://github.com/basicmachines-co/basic-memory/issues/1581) describe
reindex shutdown hangs and quadratic vector cleanup in 0.23.2. Their upstream
fixes are already in 1.0.0. This overlay addresses the separately reproduced
search-index writer contention; successful CLI exit is part of restore validation.

## Hybrid search

The default search mode is `hybrid`, combining SQLite FTS5 with `sqlite-vec`.
FastEmbed runs `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`
(384 dimensions) locally for Swedish and other supported languages. The model is
downloaded on first use and cached on the retained PVC at `/data/cache/fastembed`.
Only model artifacts are downloaded; note text is not sent to an embedding API.
The container requests 1 GiB RAM, allows 3 GiB, and uses two inference threads
within a two-core CPU limit. The 3 GiB limit leaves room for a full embedding
rebuild alongside the running server; the restore drill exceeded the former 2 GiB limit. The startup probe allows up to 15 minutes for a cold
start. Reranking remains disabled.

After first enabling semantic search, restoring notes, or changing the embedding
model, rebuild derived vectors during maintenance with exclusive access to SQLite.
For full recovery, stop the server first and run an isolated Job mounting the
same restored PVC, with the same configuration and `BASIC_MEMORY_INDEX_CHANGES=false`:

```bash
basic-memory reindex --full --search -p main
basic-memory reindex --embeddings -p main
```

Run kubectl over SSH on the control-plane node as described in the repository
instructions. The opt-in `upgrade-validation/render.py index` shows the maintenance
Job; do not run it concurrently with its server. Restart the server and verify
explicit `text`, `semantic`, `hybrid`, and default MCP searches after indexing.
New and edited notes are indexed by the existing change watcher.
To use text-only retrieval, set `BASIC_MEMORY_DEFAULT_SEARCH_TYPE=text` in Git
and reconcile Flux; semantic indexing remains available in 1.0. Keep the
Markdown files and PVC intact.

## Connect

Clients must be on the LAN or the existing Tailscale subnet route. Resolve
`memory.k3s.nu` to `192.168.50.75` locally. Do not publish an A/AAAA/CNAME record or
Cloudflare Tunnel route. The existing DNS01 issuer supplies the HTTPS certificate.

Endpoint: `https://memory.k3s.nu/mcp` (MCP Streamable HTTP).
Use `Authorization: Basic <base64(username:password)>` over verified HTTPS.
The `codex` and `agent` accounts share the project; neither has per-note restrictions.
Credential revocation means replacing that user's bcrypt entry in the SOPS Secret.
The backend port is reachable only from Traefik pods; use the authenticated endpoint
from other cluster workloads too.

On Jan's Mac the passwords are in the login Keychain, service
`basic-memory.k3s.nu`, accounts `codex` and `agent`. Codex uses a header helper in
`~/.codex/helpers/basic-memory-headers.py`, rather than plaintext configuration.
This was verified with the desktop app's bundled Codex 0.155.0-alpha.9.2. The
separate CLI 0.146.0 does not support header helpers and needs a compatible version
before it can use this authentication configuration.
Own agents should read their account from a secret store and never log headers.
Do not put personal notes, passwords, or decrypted Secrets in Git.

Basic Memory 1.0 exposes only the 12 `bm_*` tools. Old `read_note`, `search_notes`,
`recent_activity`, and write/edit tool names no longer exist. Pass `project="main"`
explicitly. Use `bm_search(mode="hybrid", compact=true)` and then `bm_read` for
selected notes; `bm_project(command="recent", since="7d", page_size=5)` replaces
recent activity. `bm_edit` uses `command` and accepts `expected_checksum` from
`bm_read` to prevent overwriting a concurrent edit. See `agent-instructions.md`.

The existing URL, Keychain helpers, private ingress and ChatGPT Secure MCP Tunnel
remain unchanged. Refresh tools in ChatGPT's Basic Memory plugin settings after
upgrading; reconnect/restart existing Codex and Claude sessions so they discover
the new tool schemas. New sessions use the updated global instructions.

The opt-in `upgrade-validation` renderer is not part of the production Kustomization.
It tests an online SQLite snapshot and byte-verified project copy on a separate PVC,
then a NAS round trip and index rebuild on another empty PVC. Test servers bind to
loopback and have no Service or Ingress. The backup test uses a separate NAS folder
and cannot rotate production archives.

Before the 1.0 migration, `basic-memory-pre-v1-rollback-data` retains a complete
0.23.2 snapshot, including a SQLite online backup, notes and model cache. Never run
1.0 against this rollback volume. To roll back before new writes, change both the
Deployment and backup CronJob claim to that PVC and pin the former 0.23.2 image in
Git. If writes have occurred after cutover, first preserve the current notes in a
verified NAS archive and reconcile those changes; the old snapshot cannot contain
them. Never simply downgrade the migrated production database in place.

## Backup and restore

`basic-memory-backup` runs at 03:30 Europe/Stockholm, on the same node as the app,
with the PVC mounted read-only and no Kubernetes token or API privileges.
The pinned Alpine image installs Python and OpenSSH from its stable distribution
repository at startup, so the backup job needs outbound package-repository access.
The job checks that accepted writes have materialized, hashes files before/after
archiving, verifies archived bytes and the NAS upload, and retains 14 successful
archives in `/volume1/k3s_backups/basic-memory`. Credentials are SOPS-encrypted.
The pinned NAS SSH key matches the existing successful OpenHAB backup log.

Backups contain the complete project files, `config/config.json`, and a SHA256
manifest. SQLite (including derived vectors), WAL, logs, and model caches are
deliberately excluded. Pending writes,
failed materializations, moved-path cleanup, changing files, or bad checksums fail
the backup instead of silently losing accepted updates. Recovery point target: 24h.

To exercise a backup: create a uniquely named Job from CronJob `basic-memory-backup`
and inspect that Job's completion and checksum log. Check the scheduled run
separately; a recent successful manual backup alone does not prove the schedule ran.

Restore into a **new** PVC, never over the running instance. Download the archive
and its `.sha256` file over SSH with the pinned host key; verify SHA256. Run
`verify_archive` from `scripts/backup.py`, extract only the validated regular files
into the empty PVC, and use UID/GID 1000. Start the same pinned app version with the
same `/data` layout, but no Ingress. Startup indexes Markdown into a new SQLite DB.
Rebuild embeddings with the same model configuration and verify note hashes and
MCP search before switching the production Deployment to
the restored PVC. Do not restore or copy a live `memory.db` file.

The namespace and PVC have Flux prune protection; the StorageClass has Retain.
Removing this application from Git intentionally leaves its data in place. Revert
configuration through Git. Do not downgrade across database migrations without
restoring a compatible backup to a new PVC.

## Rollout verification

The Basic Memory GitHub workflow validates the file-backup code and Kustomize build.
Its public-boundary job has no cluster credentials or Tailscale: it tests the current
WAN IPv4 with TLS SNI/Host `memory.k3s.nu`, also with a forged forwarded header,
and requires public DNS to be absent. Update the workflow's default address if the
ISP changes it, and rerun after router, ingress, or tunnel changes.

Keep personal content out until this public-network check and private TLS/auth
checks pass. If public access is discovered, disable this app's IngressRoute in Git
and reconcile Flux before adding data. An absent DNS record alone is not isolation.

Acceptance also requires authenticated cross-client create/read/search/update/delete,
unauthenticated 401s, NetworkPolicy denial from other pods, persistence across restart
and worker relocation, and NAS restoration with index rebuild on an isolated volume.
Prometheus alerts cover no ready replica for 5m, no successful scheduled backup for
30h, and volume usage above 80% for 15m.

References: [Basic Memory release](https://github.com/basicmachines-co/basic-memory/releases/tag/v1.0.0),
[configuration](https://docs.basicmemory.com/reference/configuration),
[Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp).
