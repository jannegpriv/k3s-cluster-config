#!/bin/sh
# Run only in the stopped-application maintenance pod, after all four RBD snapshots.
set -eu
set -o pipefail
ARCHIVE=openhab-migration-20260929-112344.tar.gz
NAS_DIR=/volume1/k3s_backups/openhab
export SSHPASS="$NAS_PASSWORD"
nas() {
  sshpass -e ssh -F /dev/null -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/ssh/nas-known-hosts -o ConnectTimeout=15 -p 4711 jannenasadm@192.168.50.25 "$@"
}
nas "test ! -e '$NAS_DIR/$ARCHIVE' && test ! -e '$NAS_DIR/$ARCHIVE.partial'"
echo "$(date -Iseconds) Creating consistent four-volume archive"
tar --numeric-owner --acls --xattrs --exclude='./userdata/backup' -czf "/work/$ARCHIVE" -C /data ./conf ./userdata ./addons ./karaf
gzip -t "/work/$ARCHIVE"
tar -tzf "/work/$ARCHIVE" > /work/archive-contents
for dir in conf userdata addons karaf; do
  grep -q "^./$dir/" /work/archive-contents
done
! grep -q '^./userdata/backup/' /work/archive-contents
sha256sum "/work/$ARCHIVE"
stat -c 'Archive bytes: %s' "/work/$ARCHIVE"
echo "$(date -Iseconds) Copying archive to NAS"
nas "umask 077; cat > '$NAS_DIR/$ARCHIVE.partial'" < "/work/$ARCHIVE"
EXPECTED=$(sha256sum "/work/$ARCHIVE" | cut -d' ' -f1)
ACTUAL=$(nas "sha256sum '$NAS_DIR/$ARCHIVE.partial'" | cut -d' ' -f1)
test "$EXPECTED" = "$ACTUAL"
nas "mv '$NAS_DIR/$ARCHIVE.partial' '$NAS_DIR/$ARCHIVE'"
echo "$(date -Iseconds) NAS archive verified SHA-256=$ACTUAL file=$ARCHIVE"
