#!/bin/bash

# Create timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/openhab/userdata/backup"
BACKUP_NAME="openhab-backup-${TIMESTAMP}"

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PATH="/volume1/openhab_backups"

# Get NAS password from environment
NAS_PASS="${NAS_PASSWORD}"

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}

# Create backup using OpenHAB's console
/openhab/runtime/bin/client "openhab:backup ${BACKUP_NAME}"

# Wait for backup to complete
sleep 30

# Compress the backup
cd ${BACKUP_DIR}
tar czf ${BACKUP_NAME}.tar.gz ${BACKUP_NAME}

# Clean up the uncompressed backup
rm -rf ${BACKUP_NAME}

# Copy to NAS using sshpass
export SSHPASS="${NAS_PASS}"
sshpass -e scp -o StrictHostKeyChecking=no -P 4711 ${BACKUP_NAME}.tar.gz "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"

# Clean up local backup after successful copy
if [ $? -eq 0 ]; then
    rm -f ${BACKUP_NAME}.tar.gz
    echo "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.tar.gz"
else
    echo "Failed to copy backup to NAS. Keeping local copy: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    exit 1
fi
