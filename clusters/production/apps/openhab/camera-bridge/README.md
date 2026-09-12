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

Also bridged: **C220 Lillstugan** `192.168.1.160` (Landet, mains, main stream 2560x1440,
~2.2 Mbit/s, SEI NALs stripped like the Huddinge C220) as `c220_lillstugan`, and
(no Tailscale hop, same LAN as the cluster) **C425 Carport** `192.168.50.35`
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
| `openhab/cameras.js` | JS Scripting rules: C425 wake (poll playlist → Ready) / auto-OFF 120 s | no — copied to `conf/automation/js/` |
| `../../../../../scripts/camera-bridge-page-gen.py` | generates `openhab/page-cameras-landet.yaml` (5 cameras: 3 mains video cards + toggles, 2 battery tap-to-start) | — |
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
4. Page: paste `openhab/page-cameras-landet.yaml` into Main UI → Settings → Pages → + →
   Layout page → Code tab (or `scripts/camera-bridge-page.sh (token from ~/.secrets/camera-bridge/oh-token)`).

## Battery camera (C425) rules baked in

- go2rtc is on-demand: no Tapo session unless an RTSP consumer is connected.
- Things: `snapshotUrl` = static `/static/camera-idle.jpg` (file `conf/html/camera-idle.jpg`,
  generated once by `scripts/camera-bridge-things.sh`). **Required**: with a blank
  `snapshotUrl` the binding silently runs a permanent `ffmpeg -skip_frame nokey`
  per camera against the bridge = permanent Tapo session (observed 2026-09-12).
  `updateImageWhen="0"`, `gifPreroll=0` → nothing polled.
- Every camera card shows the **latest still** (`conf/html/<cam>-last.jpg`, extracted
  by `cameras.js` from the newest segment whenever a stream stops). For the C425s
  tapping the still sends `startStream` ON; a player replaces it once `cameras.js` has polled the
  HLS endpoint and seen a playlist with segments (`*_Ready`). Cold start is 10-40 s
  (camera wake, first Tapo attempt often refused) - far beyond the binding's 4.5 s
  wait, and Safari's native HLS never retries a 404 playlist. The rule switches the
  stream OFF after 120 s max; a red button stops it earlier. C425 things use plain `delete_segments` (the rule
  removes the stale playlist at wake; the player never spans a restart).
- The binding keeps HLS (and thus the Tapo session) alive ~64 s after the last
  playlist request; expect the camera to report "awake" for about that long
  after closing the popup.

## Permanent stream (mains-powered cameras)

Each camera has a `<Cam>_PermanentStream` Switch (toggle on the pages) linked to the
binding's `startStream` channel. ON keeps ffmpeg → bridge → Tapo running until OFF:
no start delay, poster always fresh, camera awake 24/7. Use only for mains-powered
cameras (C720). The C425 toggles carry a battery warning and default OFF.

## HLS quirks of the 5.2.x IP Camera binding (learned the hard way)

- `CameraServlet` only skips its 4.5 s `HLS_STARTUP_DELAY_MS` when `Ffmpeg.isAlive()`
  is true, and `Ffmpeg.java` never sets `notFrozen` for the HLS format → **every**
  playlist request takes ~4.5 s, for every camera (C220 too). Players need a wide
  window: `-hls_time 4 -hls_list_size 6` (24 s).
- ffmpeg restarts often (64 s idle stop, page preload, Things reload) and would
  restart `MEDIA-SEQUENCE` at 0 → Video.js crashes in `calculateBaseTime_`, Safari
  reports "corruption". `-hls_flags append_list+discont_start` keeps the sequence
  monotonic across restarts and marks the timeline reset.
- A Things-file reload leaves the old handler's ffmpeg running ~60 s beside the new
  one, both writing the same playlist. `camera-bridge-things.sh` kills bridge ffmpeg
  before copying.
- Without `-map`, ffmpeg picks the camera's 8 kHz G.711 audio for the AAC track;
  `-map 0:v:0 -map 1:a:0` selects the silent 44.1 kHz `aevalsrc` instead.
- `oh-video-card` with `startManually` still fetches the playlist on page load
  (preload=metadata) → the C720 pipeline starts whenever the page is open and idles
  out 64 s later. Battery cameras therefore live only on popup pages.

## Also applied to the existing C220 (`ipcamera:onvif:10ce3f91aa`, UI-managed)

Same `hlsOutOptions` plus `-bsf:v filter_units=remove_types=6` (the C220 emits
malformed SEI NAL units that Safari rejects), set via full `PUT /rest/things/<uid>`
(`PUT .../config` returns 500 in 5.2.1). Its card was removed from the Overview
page (together with the Nest Landet baksida image card) and now lives on the Kameror
page as `C220_Arbetsrum_PermanentStream` / still `c220_arbetsrum-last.jpg`. Not in Git - lives in openHAB's jsondb.

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
3. Main UI → Settings → Pages → delete `cameras_landet`.
