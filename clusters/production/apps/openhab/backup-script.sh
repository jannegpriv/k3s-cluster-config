#!/bin/sh

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PATH="/volume1/k3s_backups/openhab"

# Get pod name
OPENHAB_POD=$(kubectl get pods -n openhab -l app=openhab-production -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPENHAB_POD" ]; then
    echo "Error: Could not find OpenHAB pod"
    exit 1
fi
echo "Found OpenHAB pod: ${OPENHAB_POD}"

# Cleanup old backups in pod
echo "Cleaning up old backups in pod..."
kubectl exec -n openhab ${OPENHAB_POD} -- find /openhab/userdata/backup -name "openhab-backup-*.zip" -type f -mtime +5 -delete

# Get NAS password from environment
NAS_PASS="${NAS_PASSWORD}"

# Create backup using official OpenHAB backup script
echo "Creating backup in OpenHAB pod..."
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/backup --full || {
    echo "Error: Backup failed"
    exit 1
}

# Create temporary directory for the transfer
TMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TMP_DIR}"

# Find the latest backup file
LATEST_BACKUP=$(kubectl exec -n openhab ${OPENHAB_POD} -- bash -c 'ls -t /openhab/userdata/backup/openhab-backup-*.zip | head -1')
if [ -z "${LATEST_BACKUP}" ]; then
    echo "Error: No backup file found in pod"
    rm -rf "${TMP_DIR}"
    exit 1
fi
echo "Found backup file: ${LATEST_BACKUP}"

# Copy backup from pod
echo "Copying backup from pod..."
BACKUP_NAME=$(basename "${LATEST_BACKUP}")
echo "Debug: LATEST_BACKUP=${LATEST_BACKUP}"
echo "Debug: BACKUP_NAME=${BACKUP_NAME}"
echo "Debug: Copying from openhab/${OPENHAB_POD}:${LATEST_BACKUP} to ${TMP_DIR}/${BACKUP_NAME}"
kubectl cp "openhab/${OPENHAB_POD}:${LATEST_BACKUP}" "${TMP_DIR}/${BACKUP_NAME}" || {
    echo "Failed to copy backup from pod. Check if backup was created successfully."
    rm -rf "${TMP_DIR}"
    exit 1
}
echo "Debug: Contents of ${TMP_DIR}:"
ls -la "${TMP_DIR}"

# Create backup directory and cleanup old backups on NAS
echo "Creating backup directory and cleaning up old backups on NAS..."
export SSHPASS="${NAS_PASS}"
sshpass -e ssh -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "mkdir -p '${NAS_PATH}' && find '${NAS_PATH}' -name 'openhab-backup-*.zip' -type f -mtime +5 -delete" || {
    echo "Failed to create backup directory on NAS"
    rm -rf "${TMP_DIR}"
    exit 1
}

# Create SSH config to force port 4711
echo "Creating SSH config..."
SSH_CONFIG_DIR="/root/.ssh"
SSH_CONFIG_FILE="${SSH_CONFIG_DIR}/config"
mkdir -p "${SSH_CONFIG_DIR}"
chmod 700 "${SSH_CONFIG_DIR}"
cat > "${SSH_CONFIG_FILE}" << EOF
Host ${NAS_HOST}
    Port 4711
EOF
chmod 600 "${SSH_CONFIG_FILE}"
echo "Debug: SSH config created at ${SSH_CONFIG_FILE}"
ls -la "${SSH_CONFIG_FILE}"
cat "${SSH_CONFIG_FILE}"

# Copy to NAS using sshpass
echo "Copying backup to NAS..."
echo "Debug: Using sshpass version:"
sshpass -V
echo "Debug: Command variables:"
echo "TMP_DIR=${TMP_DIR}"
echo "BACKUP_NAME=${BACKUP_NAME}"
echo "NAS_USER=${NAS_USER}"
echo "NAS_HOST=${NAS_HOST}"
echo "NAS_PATH=${NAS_PATH}"
echo "Debug: Full command:"
echo "sshpass -e scp -rv -O -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -F ${SSH_CONFIG_FILE} \"${TMP_DIR}/${BACKUP_NAME}\" ${NAS_USER}@${NAS_HOST}:${NAS_PATH}"
echo "Debug: Attempting to copy file using scp..."
export SSHPASS="${NAS_PASS}"
sshpass -e scp -rv -O -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -F "${SSH_CONFIG_FILE}" "${TMP_DIR}/${BACKUP_NAME}" ${NAS_USER}@${NAS_HOST}:${NAS_PATH} || {
    echo "Failed to copy backup to NAS"
    echo "Debug: Testing SSH connection..."
    sshpass -e ssh -v -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "ls -la \"${NAS_PATH}\""
    rm -rf "${TMP_DIR}"
    exit 1
}

# Clean up temporary directory
echo "Backup completed successfully. Cleaning up..."
rm -rf "${TMP_DIR}"

# Keep only the 5 most recent backups in the pod
echo "Cleaning up old backups..."
kubectl exec -n openhab ${OPENHAB_POD} -- bash -c 'cd /openhab/userdata/backup && ls -t *.zip | tail -n +6 | xargs -r rm --'

# Keep only the 5 most recent backups on NAS
echo "Cleaning up old backups on NAS..."
sshpass -e ssh -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "cd '${NAS_PATH}' && ls -t *.zip | tail -n +6 | xargs -r rm --" || {
    echo "Warning: Failed to clean up old backups on NAS"
    # Don't exit with error as the backup was successful
}

echo "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.zip"
