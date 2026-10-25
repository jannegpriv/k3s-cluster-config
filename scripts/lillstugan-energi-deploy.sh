#!/usr/bin/env bash
# Deploy the "Lillstugan just nu" energy page to openHAB:
#   - lillstugan.items        -> conf/items/
#   - lillstugan-justnu.js    -> conf/automation/js/   (text + badges rule)
#   - photo (optional)        -> conf/html/lillstugan.jpg (served as /static/lillstugan.jpg)
#   - widgets + page          -> Main UI via REST (PUT, POST if new)
# Targets:
#   huddinge  K3s pod openhab-production-0 (default). Token ~/.secrets/camera-bridge/oh-token
#   landet    Pi openhab3 (openHABian, SSH key as openhabian). Token ~/.secrets/openhab-landet/api-token
#             The page there has no Lynk & Co card and uses the native outdoor temperature item.
# The photo is NOT kept in Git (public repo); pass its path when it changes.
# Usage: scripts/lillstugan-energi-deploy.sh [huddinge|landet] [photo.jpg]
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:-huddinge}"
PHOTO="${2:-}"
DIR="clusters/production/apps/openhab/lillstugan-energi"
SSH="ssh -F /dev/null"

case "$TARGET" in
  huddinge)
    BASE="http://192.168.50.75:30080"
    TOKFILE="$HOME/.secrets/camera-bridge/oh-token"
    ;;
  landet)
    BASE="http://192.168.1.86:8080"
    TOKFILE="$HOME/.secrets/openhab-landet/api-token"
    ;;
  *) echo "usage: $0 [huddinge|landet] [photo.jpg]" >&2; exit 1 ;;
esac
OPENHAB_TOKEN="${OPENHAB_TOKEN:-$( [ -s "$TOKFILE" ] && cat "$TOKFILE" )}"
: "${OPENHAB_TOKEN:?no token: put it in $TOKFILE (Main UI > profile > Create new API token)}"

if [ "$TARGET" = huddinge ]; then
  HOST="janne@192.168.50.75"
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
else
  HOST="openhabian@192.168.1.86"
  scp -F /dev/null -q "$DIR/lillstugan.items" "$HOST:/etc/openhab/items/lillstugan.items"
  scp -F /dev/null -q "$DIR/lillstugan-justnu.js" "$HOST:/etc/openhab/automation/js/lillstugan-justnu.js"
  [ -n "$PHOTO" ] && scp -F /dev/null -q "$PHOTO" "$HOST:/etc/openhab/html/lillstugan.jpg"
  $SSH "$HOST" 'ls -l /etc/openhab/items/lillstugan.items /etc/openhab/automation/js/lillstugan-justnu.js /etc/openhab/html/lillstugan.jpg 2>&1'
fi

# YAML -> JSON with Ruby (stdlib on macOS; PyYAML is not installed there).
# For Landet the page drops the Lynk & Co column and points the hero at the native items.
put() { # kind file
  local kind="$1" f="$2" uid body code
  uid="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["uid"]' "$f")"
  body="$(ruby -ryaml -rjson -e '
    y = YAML.load_file(ARGV[0])
    if ARGV[1] == "landet" && y["component"] == "oh-layout-page"
      walk = lambda do |node|
        (node["slots"] || {}).each_value do |children|
          children.reject! { |c| (c.dig("slots", "default") || []).any? { |w| w["component"] == "widget:lillstugan_bil" } }
          children.each do |c|
            if c["component"] == "widget:lillstugan_hero"
              c["config"] = (c["config"] || {}).merge("tempItem" => "Gateway_Device_Outdoor_Temperature")
            end
            c["config"]["large"] = "100" if c["component"] == "oh-grid-col" && c["config"]["large"] == "40"
            walk.call(c)
          end
        end
      end
      walk.call(y)
    end
    puts JSON.generate(y)' "$f" "$TARGET")"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/rest/ui/components/ui:$kind/$uid" \
    -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  if [ "$code" = "404" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/rest/ui/components/ui:$kind" \
      -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" --data "$body")"
  fi
  echo "$TARGET ui:$kind/$uid -> HTTP $code"
}
for w in widget-lillstugan-kort.yaml widget-lillstugan-hero.yaml widget-lillstugan-bil.yaml; do put widget "$DIR/$w"; done
put page "$DIR/page-lillstugan.yaml"
