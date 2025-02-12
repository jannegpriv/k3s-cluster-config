#!/bin/sh

# Create timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openhab-backup-${TIMESTAMP}"

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PATH="/volume1/openhab_backups"
OPENHAB_POD="openhab-production-0"

# Get NAS password from environment
NAS_PASS="${NAS_PASSWORD}"

# Create backup using kubectl exec
echo "Creating backup in OpenHAB pod..."
# Create backup in OpenHAB pod
echo "Creating backup in OpenHAB pod..."
kubectl exec -n openhab ${OPENHAB_POD} -- bash -c "
  export OPENHAB_CONF=/openhab/conf && \
  export OPENHAB_USERDATA=/openhab/userdata && \
  export OPENHAB_BACKUPS=/openhab/userdata/backup && \
  mkdir -p \$OPENHAB_BACKUPS && \
  cd /openhab && \
  /openhab/runtime/bin/backup --noninteractive ${BACKUP_NAME}.zip && \
  mv \$OPENHAB_BACKUPS/${BACKUP_NAME}.zip userdata/backup/"

# Create temporary directory
TMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TMP_DIR}"

# Copy the backup from the pod
echo "Copying backup from pod..."
kubectl cp openhab/${OPENHAB_POD}:/openhab/userdata/backup/${BACKUP_NAME}.zip ${TMP_DIR}/${BACKUP_NAME}.zip

# Copy to NAS using sshpass
echo "Copying backup to NAS..."
export SSHPASS="${NAS_PASS}"
sshpass -e scp -o StrictHostKeyChecking=no -P 4711 ${TMP_DIR}/${BACKUP_NAME}.zip "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"

# Clean up backups
if [ $? -eq 0 ]; then
    echo "Cleaning up temporary files..."
    kubectl exec -n openhab ${OPENHAB_POD} -- rm -f /openhab/userdata/backup/${BACKUP_NAME}.zip
    rm -rf ${TMP_DIR}
    echo "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.zip"
else
    echo "Failed to copy backup to NAS. Backup remains in OpenHAB pod and ${TMP_DIR}"
    exit 1
fi
