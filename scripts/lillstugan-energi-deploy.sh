#!/usr/bin/env bash
# Deploy the "Lillstugan just nu" energy page to openHAB (Huddinge):
#   - lillstugan.items        -> conf/items/
#   - lillstugan-justnu.js    -> conf/automation/js/   (text + badges rule)
#   - photo (optional)        -> conf/html/lillstugan.jpg (served as /static/lillstugan.jpg)
#   - widgets + page          -> Main UI via REST (PUT, POST if new)
# The photo is NOT kept in Git (public repo); pass its path as the first argument when it
# changes. openHAB API token: ~/.secrets/camera-bridge/oh-token (or OPENHAB_TOKEN env).
# Usage: scripts/lillstugan-energi-deploy.sh [photo.jpg] [base-url]
set -euo pipefail
cd "$(dirname "$0")/.."
PHOTO="${1:-}"
BASE="${2:-http://192.168.50.75:30080}"
HOST="janne@192.168.50.75"
SSH="ssh -F /dev/null"
TOKFILE="${CAMERA_BRIDGE_SECRETS_DIR:-$HOME/.secrets/camera-bridge}/oh-token"
OPENHAB_TOKEN="${OPENHAB_TOKEN:-$( [ -s "$TOKFILE" ] && cat "$TOKFILE" )}"
: "${OPENHAB_TOKEN:?no token: put it in $TOKFILE (Main UI > profile > Create new API token)}"
DIR="clusters/production/apps/openhab/lillstugan-energi"
POD="openhab-production-0"
C="openhab514"

files=("$DIR/lillstugan.items" "$DIR/lillstugan-justnu.js")
[ -n "$PHOTO" ] && files+=("$PHOTO")
scp -F /dev/null -q "${files[@]}" "${HOST}:/tmp/"
photo_cmd=""
if [ -n "$PHOTO" ]; then
  pb="$(basename "$PHOTO")"
  photo_cmd="kubectl -n openhab cp '/tmp/$pb' $POD:/openhab/conf/html/lillstugan.jpg -c $C && rm -f '/tmp/$pb' &&"
fi
$SSH "$HOST" "export KUBECONFIG=\$HOME/.kube/config; set -e
  $photo_cmd
  kubectl -n openhab cp /tmp/lillstugan.items $POD:/openhab/conf/items/lillstugan.items -c $C
  kubectl -n openhab cp /tmp/lillstugan-justnu.js $POD:/openhab/conf/automation/js/lillstugan-justnu.js -c $C
  rm -f /tmp/lillstugan.items /tmp/lillstugan-justnu.js
  kubectl -n openhab exec $POD -c $C -- sh -c 'cd /openhab/conf; chown openhab:openhab items/lillstugan.items automation/js/lillstugan-justnu.js html/lillstugan.jpg 2>/dev/null; ls -l items/lillstugan.items automation/js/lillstugan-justnu.js html/lillstugan.jpg 2>&1'"

# YAML -> JSON with Ruby (stdlib on macOS; PyYAML is not installed there)
put() { # kind file
  local kind="$1" f="$2" uid body code
  uid="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["uid"]' "$f")"
  body="$(ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$f")"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/rest/ui/components/ui:$kind/$uid" \
    -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  if [ "$code" = "404" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/rest/ui/components/ui:$kind" \
      -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  fi
  echo "ui:$kind/$uid -> HTTP $code"
}
for w in widget-lillstugan-kort.yaml widget-lillstugan-hero.yaml widget-lillstugan-bil.yaml; do put widget "$DIR/$w"; done
put page "$DIR/page-lillstugan.yaml"
