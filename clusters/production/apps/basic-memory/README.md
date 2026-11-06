# Basic Memory pilot

One ARM64 replica of Basic Memory 0.23.2, Markdown in `/data/memory`, configuration
and rebuildable SQLite index in `/data/config`, on the retained 5 GiB Ceph RBD PVC.
The Deployment uses Recreate; brief update interruptions are expected. Hybrid search
uses local FastEmbed inference; no external model API or telemetry is enabled.
App pods have no Kubernetes token.

## Hybrid search

The default search mode is `hybrid`, combining SQLite FTS5 with `sqlite-vec`.
FastEmbed runs `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`
(384 dimensions) locally for Swedish and other supported languages. The model is
downloaded on first use and cached on the retained PVC at `/data/cache/fastembed`.
Only model artifacts are downloaded; note text is not sent to an embedding API.
The container requests 1 GiB RAM, allows 2 GiB, and uses two inference threads
within a two-core CPU limit. The startup probe allows up to 15 minutes for a cold
start. Reranking remains disabled.

After first enabling semantic search, restoring notes, or changing the embedding
model, rebuild derived vectors in the running container:

```bash
kubectl -n basic-memory exec deployment/basic-memory -- basic-memory reindex --embeddings -p main
```

Run kubectl over SSH on the control-plane node as described in the repository
instructions. Verify explicit `text`, `vector`, `hybrid`, and default MCP searches
after indexing. New and edited notes are indexed by the existing change watcher.
To roll back retrieval behavior, set `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false`
and `BASIC_MEMORY_DEFAULT_SEARCH_TYPE=text` in Git and reconcile Flux; keep the
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
and inspect its completion and log. Creating a manual Job does not update the
CronJob's last-successful timestamp; the normal scheduled run does.

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

References: [Basic Memory release](https://github.com/basicmachines-co/basic-memory/releases/tag/v0.23.2),
[configuration](https://docs.basicmemory.com/reference/configuration),
[Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp).
