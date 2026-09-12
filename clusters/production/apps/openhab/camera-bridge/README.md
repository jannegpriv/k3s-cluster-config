# camera-bridge — Landet cameras (Tapo C720 / C425) in openHAB Huddinge

```
C720 192.168.1.228 / C425 192.168.1.83  (Landet LAN)
   │  Tapo protocol, TCP 8800
   ▼
openhab3 (Landet Pi, Tailscale subnet router 192.168.1.0/24)
   │  Tailscale
   ▼
camera-bridge pod (ns openhab): tailscale --accept-routes  +  go2rtc
   │  RTSP :8554 (auth), ClusterIP camera-bridge.openhab.svc.cluster.local
   ▼
openHAB IP Camera binding (ipcamera:generic) → ffmpeg → HLS in /dev/shm
   │  /ipcamera/<thing>/ipcamera.m3u8 (same origin as Main UI)
   ▼
Main UI page "Kameror Landet" (oh-video-card, Video.js)
```

Verified 2026-09-12 from the Mac over Tailscale: both cameras deliver H.264
1280×720 via `tapo://…?subtype=1` with go2rtc 1.9.14. Direct RTSP/ONVIF on
the cameras refused connections, so the Tapo protocol path is the one used.

Also bridged (no Tailscale hop, same LAN as the cluster): **C425 Carport** `192.168.50.35`
as stream `c425_carport` — useful as the first test target because it isolates the
Tapo/go2rtc path from the Tailscale routing.

## Files

| File | Purpose | Flux-managed |
|---|---|---|
| `deployment.yaml` | Tailscale (kernel mode, `NET_ADMIN`, `/dev/net/tun`, `--accept-routes`, `--accept-dns=false`) + go2rtc in one pod, `Recreate` | yes |
| `pvc.yaml` | Tailscale node state (`TS_STATE_DIR`), 100Mi RBD | yes |
| `service.yaml` | ClusterIP `camera-bridge:8554` (RTSP only; API bound to 127.0.0.1, WebRTC off) | yes |
| `secret.enc.yaml` | SOPS: `TS_AUTHKEY`, rendered `go2rtc.yaml` (Tapo pw URL-encoded, RTSP creds), `rtsp-username/-password` | yes (Flux decrypts with `sops-gpg`) |
| `openhab/cameras.things.tmpl` | the two `ipcamera:generic` Things (creds filled at render time) | no — copied to the conf PVC |
| `openhab/cameras.items` | `*_PermanentStream` switches → binding channel `startStream` (HLS kept running while ON; mains cameras only) | no — copied to the conf PVC |
| `openhab/page-*.yaml` | Main UI pages (overview + C425 live popup) | no — Main UI (jsondb) |
| `../../../../../scripts/camera-bridge-secret.sh` | builds + encrypts the Secret from local masked files | — |
| `../../../../../scripts/camera-bridge-things.sh` | renders the Things file (RTSP creds from `~/.secrets/camera-bridge/`) and `kubectl cp`s it into `openhab-production-0` | — |
| `../../../../../scripts/camera-bridge-page.sh` | optional: PUT the pages via REST with an API token | — |

## First-time setup

1. Local secrets (never in Git), entered with a masked prompt:
   ```bash
   mkdir -p ~/.secrets/camera-bridge && chmod 700 ~/.secrets/camera-bridge
   read -s p; printf '%s' "$p" > ~/.secrets/camera-bridge/tapo-password; unset p   # Tapo cloud account pw
   read -s k; printf '%s' "$k" > ~/.secrets/camera-bridge/ts-authkey;    unset k   # tskey-auth-…
   ```
   Tailscale auth key: admin console → Settings → Keys → Generate. Non-reusable,
   not ephemeral, "pre-approved" on (personal tailnet, no tags/ACL needed — the
   default policy allows all members' devices to talk). `TS_AUTH_ONCE=true` means
   the key is only consumed on the first start; identity then lives on the PVC.
   Node-key expiry (default 180 d) → either "Disable key expiry" on the node in
   the admin console or rotate the key + delete the PVC.
2. `scripts/camera-bridge-secret.sh` → commit `secret.enc.yaml` → push → Flux.
3. `scripts/camera-bridge-things.sh` (after the bridge pod is Ready).
4. Pages: paste `openhab/page-cameras-landet-c425-live.yaml`,
   `openhab/page-cameras-carport-c425-live.yaml`, then `openhab/page-cameras-landet.yaml` into Main UI → Settings → Pages → + →
   Layout page → Code tab (or `scripts/camera-bridge-page.sh (token from ~/.secrets/camera-bridge/oh-token)`).

## Battery camera (C425) rules baked in

- go2rtc is on-demand: no Tapo session unless an RTSP consumer is connected.
- Things: `snapshotUrl` = static `/static/camera-idle.jpg` (file `conf/html/camera-idle.jpg`,
  generated once by `scripts/camera-bridge-things.sh`). **Required**: with a blank
  `snapshotUrl` the binding silently runs a permanent `ffmpeg -skip_frame nokey`
  per camera against the bridge = permanent Tapo session (observed 2026-09-12).
  `updateImageWhen="0"`, `gifPreroll=0` → nothing polled.
- Overview page holds **no** player for the C425 — only a button opening a
  popup page; the HLS playlist is first requested when the popup's player starts.
- The binding keeps HLS (and thus the Tapo session) alive ~64 s after the last
  playlist request; expect the camera to report "awake" for about that long
  after closing the popup.

## Permanent stream (mains-powered cameras)

Each camera has a `<Cam>_PermanentStream` Switch (toggle on the pages) linked to the
binding's `startStream` channel. ON keeps ffmpeg → bridge → Tapo running until OFF:
no start delay, poster always fresh, camera awake 24/7. Use only for mains-powered
cameras (C720). The C425 toggles carry a battery warning and default OFF.

## Operations

- Logs: `kubectl -n openhab logs deploy/camera-bridge -c tailscale` / `-c go2rtc`
- Route check: `kubectl -n openhab exec deploy/camera-bridge -c tailscale -- tailscale status`
- Restart bridge only: `kubectl -n openhab rollout restart deploy/camera-bridge`
  (state PVC keeps the node identity; Recreate avoids two tailscaled at once)
- HLS segments live in `/dev/shm/ipcamera/<thing>/` inside `openhab514`
  (64 MiB tmpfs; 4×2 s segments per camera ≈ a few MB). Cleared on restart.

## Rollback / removal

1. `git revert` the camera-bridge commits (or remove `- camera-bridge` from
   `openhab/kustomization.yaml`) → push → Flux prunes Deployment/Service/PVC/Secret.
   Delete the node `camera-bridge` in the Tailscale admin console.
2. Delete `/openhab/conf/things/cameras.things` in the openHAB pod (the two
   Things vanish; existing C220 `ipcamera:onvif:10ce3f91aa` and all other Things
   are untouched).
3. Main UI → Settings → Pages → delete `cameras_landet`, `cameras_landet_c425_live`, `cameras_carport_c425_live`.
