#!/usr/bin/env bash
# Create/update the two Main UI pages through openHAB's REST API (optional -
# the YAML can also be pasted into the page editor's Code tab).
# openHAB API token: read from ~/.secrets/camera-bridge/oh-token (or OPENHAB_TOKEN env).
# Usage: scripts/camera-bridge-page.sh [base-url]   (runs the YAML->JSON step on the master, which has PyYAML)
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-http://192.168.50.75:30080}"
TOKFILE="${CAMERA_BRIDGE_SECRETS_DIR:-$HOME/.secrets/camera-bridge}/oh-token"
OPENHAB_TOKEN="${OPENHAB_TOKEN:-$( [ -s "$TOKFILE" ] && cat "$TOKFILE" )}"
: "${OPENHAB_TOKEN:?no token: put it in $TOKFILE (Main UI > profile > Create new API token)}"
DIR="clusters/production/apps/openhab/camera-bridge/openhab"
python3 -c 'import yaml' 2>/dev/null || { echo "needs PyYAML: pip3 install pyyaml" >&2; exit 1; }
for f in page-cameras-landet-c425-live.yaml page-cameras-carport-c425-live.yaml page-cameras-landet.yaml; do
  uid="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["uid"])' "$DIR/$f")"
  body="$(python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$DIR/$f")"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/rest/ui/components/ui:page/$uid" \
    -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  if [ "$code" = "404" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/rest/ui/components/ui:page" \
      -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  fi
  echo "$uid -> HTTP $code"
done
