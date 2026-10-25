#!/usr/bin/env bash
# Deploy the "Huddinge just nu" page to the Huddinge openHAB (K3s pod openhab-production-0):
#   - huddinge.items          -> conf/items/
#   - huddinge-justnu.js      -> conf/automation/js/   (text, badges, daily figures, forecast)
#   - widgets + page          -> Main UI via REST (PUT, POST if new)
# The page also uses lillstugan_kort and lillstugan_bil; deploy those with
# scripts/lillstugan-energi-deploy.sh huddinge.
# Token: ~/.secrets/camera-bridge/oh-token (or OPENHAB_TOKEN).
# Usage: scripts/huddinge-energi-deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="clusters/production/apps/openhab/huddinge-energi"
BASE="http://192.168.50.75:30080"
HOST="janne@192.168.50.75"
POD="openhab-production-0"
C="openhab514"
TOKFILE="$HOME/.secrets/camera-bridge/oh-token"
OPENHAB_TOKEN="${OPENHAB_TOKEN:-$( [ -s "$TOKFILE" ] && cat "$TOKFILE" )}"
: "${OPENHAB_TOKEN:?no token: put it in $TOKFILE (Main UI > profile > Create new API token)}"

scp -F /dev/null -q "$DIR/huddinge.items" "$DIR/huddinge-justnu.js" "${HOST}:/tmp/"
ssh -F /dev/null "$HOST" "export KUBECONFIG=\$HOME/.kube/config; set -e
  kubectl -n openhab cp /tmp/huddinge.items $POD:/openhab/conf/items/huddinge.items -c $C
  kubectl -n openhab cp /tmp/huddinge-justnu.js $POD:/openhab/conf/automation/js/huddinge-justnu.js -c $C
  rm -f /tmp/huddinge.items /tmp/huddinge-justnu.js
  kubectl -n openhab exec $POD -c $C -- sh -c 'cd /openhab/conf; chown openhab:openhab items/huddinge.items automation/js/huddinge-justnu.js; ls -l items/huddinge.items automation/js/huddinge-justnu.js'"

# YAML -> JSON with Ruby (stdlib on macOS; PyYAML is not installed there).
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
for w in widget-huddinge-hero.yaml widget-huddinge-el.yaml; do put widget "$DIR/$w"; done
put page "$DIR/page-huddinge.yaml"
