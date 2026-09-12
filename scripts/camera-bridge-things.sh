#!/usr/bin/env bash
# Render cameras.things from the template + SOPS secret and copy it into the
# running openHAB pod (/openhab/conf/things/). Same "reference copy in Git,
# live file on the conf PVC" pattern as sitemaps/watch.sitemap. Nothing is
# overwritten except this one file; openHAB hot-reloads .things files.
# Usage: scripts/camera-bridge-things.sh [ssh-host]   (default janne@192.168.50.75)
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:-janne@192.168.50.75}"
SSH="ssh -F /dev/null -o ConnectTimeout=10"
TMPL="clusters/production/apps/openhab/camera-bridge/openhab/cameras.things.tmpl"
umask 077
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# The SOPS private key lives only in the cluster (Flux), so read the RTSP creds
# from the same local masked files camera-bridge-secret.sh used.
SRC="${CAMERA_BRIDGE_SECRETS_DIR:-$HOME/.secrets/camera-bridge}"
[ -s "$SRC/rtsp-password" ] || { echo "missing $SRC/rtsp-password (run camera-bridge-secret.sh first)" >&2; exit 1; }
U="openhab"; P="$(cat "$SRC/rtsp-password")"
python3 - "$TMPL" "$TMP/cameras.things" "$U" "$P" <<'PY'
import sys
t, o, u, p = sys.argv[1:5]
open(o, "w").write(open(t).read().replace("@@RTSP_USER@@", u).replace("@@RTSP_PASS@@", p))
PY
cp "clusters/production/apps/openhab/camera-bridge/openhab/cameras.items" "$TMP/cameras.items"
cp "clusters/production/apps/openhab/camera-bridge/openhab/cameras.js" "$TMP/cameras.js"
scp -F /dev/null -q "$TMP/cameras.things" "$TMP/cameras.items" "$TMP/cameras.js" "${HOST}:/tmp/"
# Static placeholder for snapshotUrl/poster (created once, 1280x720 dark grey).
$SSH "$HOST" 'export KUBECONFIG=$HOME/.kube/config; kubectl -n openhab exec openhab-production-0 -c openhab514 -- sh -c "test -s /openhab/conf/html/camera-idle.jpg || (ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=0x1f2933:s=1280x720 -frames:v 1 -q:v 4 /openhab/conf/html/camera-idle.jpg && chown openhab:openhab /openhab/conf/html/camera-idle.jpg); ls -l /openhab/conf/html/camera-idle.jpg"'
# Stop any running bridge ffmpeg first and EMPTY (never remove) the HLS dirs: the
# binding only mkdirs them when its Ffmpeg object is created; after a Things reload
# the handler is reused, so a removed dir makes ffmpeg fail forever (restart every 8 s). on a Things reload the old handler's
# HLS ffmpeg keeps running ~60 s next to the new one and both write the same
# playlist (sequence flaps -> players break). They restart on demand.
$SSH "$HOST" 'export KUBECONFIG=$HOME/.kube/config; kubectl -n openhab exec openhab-production-0 -c openhab514 -- sh -c "pkill -f \"^/usr/bin/ffmpeg .*camera-bridge\" || true; for d in c720_lillstugan c425_landet_baksida c425_carport; do mkdir -p /dev/shm/ipcamera/\$d; rm -f /dev/shm/ipcamera/\$d/*; chown openhab:openhab /dev/shm/ipcamera/\$d; done"'
$SSH "$HOST" 'export KUBECONFIG=$HOME/.kube/config; kubectl -n openhab cp /tmp/cameras.things openhab-production-0:/openhab/conf/things/cameras.things -c openhab514 && kubectl -n openhab cp /tmp/cameras.items openhab-production-0:/openhab/conf/items/cameras.items -c openhab514 && kubectl -n openhab cp /tmp/cameras.js openhab-production-0:/openhab/conf/automation/js/cameras.js -c openhab514 && rm -f /tmp/cameras.things /tmp/cameras.items /tmp/cameras.js && kubectl -n openhab exec openhab-production-0 -c openhab514 -- sh -c "rm -f /openhab/conf/rules/cameras.rules; chown openhab:openhab /openhab/conf/things/cameras.things /openhab/conf/items/cameras.items /openhab/conf/automation/js/cameras.js; ls -l /openhab/conf/things/cameras.things /openhab/conf/items/cameras.items /openhab/conf/automation/js/cameras.js"'
echo "deployed; watch: kubectl -n openhab exec openhab-production-0 -c openhab514 -- tail -f /openhab/userdata/logs/openhab.log | grep -i ipcamera"
