#!/usr/bin/env bash
# Build + SOPS-encrypt the camera-bridge Secret WITHOUT echoing any secret.
#
# Inputs (local files, never in Git, create with a masked prompt, e.g.
#   read -s p; printf '%s' "$p" > ~/.secrets/camera-bridge/tapo-password; unset p):
#   ~/.secrets/camera-bridge/tapo-password   Tapo *cloud account* password (owns the cameras)
#   ~/.secrets/camera-bridge/ts-authkey      Tailscale auth key (tskey-auth-..., non-reusable is fine)
#   ~/.secrets/camera-bridge/rtsp-password   optional; generated if missing
#
# Output: clusters/production/apps/openhab/camera-bridge/secret.enc.yaml (encrypted)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${CAMERA_BRIDGE_SECRETS_DIR:-$HOME/.secrets/camera-bridge}"
OUT="clusters/production/apps/openhab/camera-bridge/secret.enc.yaml"
for f in tapo-password ts-authkey; do
  [ -s "$SRC/$f" ] || { echo "missing $SRC/$f" >&2; exit 1; }
done
[ -s "$SRC/rtsp-password" ] || { umask 077; openssl rand -hex 16 > "$SRC/rtsp-password"; }
RTSP_USER="openhab"
umask 077
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Python does the URL-encoding of the Tapo password and the YAML quoting;
# nothing secret ever hits argv or stdout.
python3 - "$SRC" "$RTSP_USER" "$TMP/plain.yaml" <<'PY'
import sys, json, urllib.parse
src, rtsp_user, out = sys.argv[1:4]
rd = lambda n: open(f"{src}/{n}").read().strip()
tapo = urllib.parse.quote(rd("tapo-password"), safe="")
rtsp_pw = rd("rtsp-password")
ts = rd("ts-authkey")
go2rtc = f"""# go2rtc for camera-bridge (rendered by scripts/camera-bridge-secret.sh)
api:
  listen: "127.0.0.1:1984"   # admin API local to the pod only
rtsp:
  listen: ":8554"
  username: {json.dumps(rtsp_user)}
  password: {json.dumps(rtsp_pw)}
webrtc:
  listen: ""                 # unused for this MVP
log:
  level: info
streams:
  # Tapo protocol (TCP 8800) over Tailscale -> openhab3 subnet router.
  # The URL user-field IS the Tapo cloud password (go2rtc convention).
  # subtype=1 = the 1280x720 sub-stream verified 2026-09-12.
  c720_lillstugan: tapo://{tapo}@192.168.1.228?subtype=1
  c425_landet_baksida: tapo://{tapo}@192.168.1.83?subtype=1
  # Huddinge carport (same LAN as the cluster, no Tailscale hop) - reference/test camera.
  c425_carport: tapo://{tapo}@192.168.50.35?subtype=1
  # Lillstugan C220 (mains, Landet LAN). subtype=1 = sub-stream (720p).
  c220_lillstugan: tapo://{tapo}@192.168.1.160?subtype=1
"""
doc = {
  "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
  "metadata": {"name": "camera-bridge", "namespace": "openhab"},
  "stringData": {
    "TS_AUTHKEY": ts,
    "go2rtc.yaml": go2rtc,
    "rtsp-username": rtsp_user,
    "rtsp-password": rtsp_pw,
  },
}
# JSON is valid YAML - no PyYAML dependency on the Mac.
open(out, "w").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
PY
# --filename-override makes .sops.yaml's creation rule (path + encrypted_regex + PGP key) apply.
sops --encrypt --filename-override "$OUT" --input-type yaml --output-type yaml "$TMP/plain.yaml" > "$OUT"
echo "wrote $OUT ($(grep -c 'ENC\[' "$OUT") encrypted fields)"
