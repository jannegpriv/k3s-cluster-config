#!/bin/bash

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
kubectl exec -n openhab ${OPENHAB_POD} -- bash -c "
  mkdir -p /openhab/userdata/backup && \
  /openhab/runtime/bin/client 'openhab:backup ${BACKUP_NAME}' && \
  cd /openhab/userdata/backup && \
  tar czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME} && \
  rm -rf ${BACKUP_NAME}"

# Copy the backup from the pod
kubectl cp openhab/${OPENHAB_POD}:/openhab/userdata/backup/${BACKUP_NAME}.tar.gz /tmp/${BACKUP_NAME}.tar.gz

# Copy to NAS using sshpass
export SSHPASS="${NAS_PASS}"
sshpass -e scp -o StrictHostKeyChecking=no -P 4711 /tmp/${BACKUP_NAME}.tar.gz "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"

# Clean up backups
if [ $? -eq 0 ]; then
    kubectl exec -n openhab ${OPENHAB_POD} -- rm -f /openhab/userdata/backup/${BACKUP_NAME}.tar.gz
    rm -f /tmp/${BACKUP_NAME}.tar.gz
    echo "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.tar.gz"
else
    echo "Failed to copy backup to NAS. Backup remains in OpenHAB pod and /tmp"
    exit 1
fi
