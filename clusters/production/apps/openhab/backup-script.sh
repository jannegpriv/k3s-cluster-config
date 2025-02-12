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
kubectl exec -n openhab ${OPENHAB_POD} -- bash -c "
  mkdir -p /openhab/userdata/backup && \
  cd /openhab/userdata/backup && \
  /openhab/runtime/bin/client 'openhab:backup ${BACKUP_NAME}' && \
  tar czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME} && \
  rm -rf ${BACKUP_NAME}"

# Create temporary directory
TMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TMP_DIR}"

# Copy the backup from the pod
echo "Copying backup from pod..."
kubectl cp openhab/${OPENHAB_POD}:/openhab/userdata/backup/${BACKUP_NAME}.tar.gz ${TMP_DIR}/${BACKUP_NAME}.tar.gz

# Copy to NAS using sshpass
echo "Copying backup to NAS..."
export SSHPASS="${NAS_PASS}"
sshpass -e scp -o StrictHostKeyChecking=no -P 4711 ${TMP_DIR}/${BACKUP_NAME}.tar.gz "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"

# Clean up backups
if [ $? -eq 0 ]; then
    echo "Cleaning up temporary files..."
    kubectl exec -n openhab ${OPENHAB_POD} -- rm -f /openhab/userdata/backup/${BACKUP_NAME}.tar.gz
    rm -rf ${TMP_DIR}
    echo "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.tar.gz"
else
    echo "Failed to copy backup to NAS. Backup remains in OpenHAB pod and ${TMP_DIR}"
    exit 1
fi
