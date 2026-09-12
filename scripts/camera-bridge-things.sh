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
scp -F /dev/null -q "$TMP/cameras.things" "${HOST}:/tmp/cameras.things"
# Static placeholder for snapshotUrl/poster (created once, 1280x720 dark grey).
$SSH "$HOST" 'export KUBECONFIG=$HOME/.kube/config; kubectl -n openhab exec openhab-production-0 -c openhab514 -- sh -c "test -s /openhab/conf/html/camera-idle.jpg || (ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=0x1f2933:s=1280x720 -frames:v 1 -q:v 4 /openhab/conf/html/camera-idle.jpg && chown openhab:openhab /openhab/conf/html/camera-idle.jpg); ls -l /openhab/conf/html/camera-idle.jpg"'
$SSH "$HOST" 'export KUBECONFIG=$HOME/.kube/config; kubectl -n openhab cp /tmp/cameras.things openhab-production-0:/openhab/conf/things/cameras.things -c openhab514 && rm -f /tmp/cameras.things && kubectl -n openhab exec openhab-production-0 -c openhab514 -- sh -c "chown openhab:openhab /openhab/conf/things/cameras.things; ls -l /openhab/conf/things/cameras.things"'
echo "deployed; watch: kubectl -n openhab exec openhab-production-0 -c openhab514 -- tail -f /openhab/userdata/logs/openhab.log | grep -i ipcamera"
