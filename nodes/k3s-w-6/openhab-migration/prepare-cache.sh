#!/bin/sh
# Execute only while the StatefulSet is at zero and the offline NAS backup is verified.
set -eu
: "${1:?Expected archive SHA-256 required}"
ARCHIVE=openhab-migration-20260929-112344.tar.gz
EXPECTED="$1"
ACTUAL=$(sha256sum "/work/$ARCHIVE" | cut -d' ' -f1)
test "$EXPECTED" = "$ACTUAL"
export SSHPASS="$NAS_PASSWORD"
REMOTE=$(sshpass -e ssh -F /dev/null -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/ssh/nas-known-hosts -p 4711 jannenasadm@192.168.50.25 "sha256sum '/volume1/k3s_backups/openhab/$ARCHIVE'" </dev/null | cut -d' ' -f1)
test "$EXPECTED" = "$REMOTE"
for dir in /data/userdata/cache /data/userdata/tmp; do
  test -d "$dir"
  test ! -L "$dir"
  stat -c 'Preserving directory owner/group/mode: %u %g %a %n' "$dir"
  find "$dir" -xdev -mindepth 1 -depth -delete
  test -z "$(find "$dir" -mindepth 1 -print -quit)"
done
echo "Cache and tmp emptied; directory ownership, configuration, JSONDB and persistence preserved"
