#!/bin/sh
set -o pipefail
set -u
export PS4='+ $(date "+%Y-%m-%dT%H:%M:%S%z") [${BASH_SOURCE}:${LINENO}] '

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"
  # flush output
  sync
}

log "Running backup script version $(date '+%Y-%m-%dT%H:%M')"
sync

trap 'log "ERROR: Script failed at line $LINENO with exit code $?"' ERR

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PATH="/volume1/k3s_backups/openhab"

log "[STEP] Detecting OpenHAB pod..."
OPENHAB_POD=$(kubectl get pods -n openhab -l app=openhab-production -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPENHAB_POD" ]; then
    log "Error: Could not find OpenHAB pod"
    exit 1
fi
log "Found OpenHAB pod: ${OPENHAB_POD}"

log "[STEP] Cleaning up old backups in pod (older than 5 days)..."
kubectl exec -n openhab ${OPENHAB_POD} -- find /openhab/userdata/backup -name "openhab-backup-*.zip" -type f -mtime +5 -delete || log "Warning: Cleanup of old backups in pod failed"

log "[STEP] Retrieving NAS password from environment..."
NAS_PASS="${NAS_PASSWORD}"

TODAY=$(date '+%y_%m_%d')
if kubectl exec -n openhab ${OPENHAB_POD} -- ls /openhab/userdata/backup/openhab-backup-${TODAY}-*.zip 1>/dev/null 2>&1; then
  log "A backup for today already exists. Skipping creation."
else
  log "[STEP] Creating backup in OpenHAB pod..."
  kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/backup --full || {
    log "Error: Backup failed (exit code $?)";
    exit 1;
  }
fi

log "[STEP] Creating temporary directory for transfer..."
TMP_DIR=$(mktemp -d)
log "Created temporary directory: ${TMP_DIR}"

log "[STEP] Finding latest backup file in pod..."
LATEST_BACKUP=$(kubectl exec -n openhab ${OPENHAB_POD} -- bash -c 'ls -t /openhab/userdata/backup/openhab-backup-*.zip | head -1')
if [ -z "${LATEST_BACKUP}" ]; then
    log "Error: No backup file found in pod"
    rm -rf "${TMP_DIR}"
    exit 1
fi
log "Found backup file: ${LATEST_BACKUP}"

log "[STEP] Copying backup from pod to local temp dir..."
BACKUP_NAME=$(basename "${LATEST_BACKUP}")
log "Debug: LATEST_BACKUP=${LATEST_BACKUP}"
log "Debug: BACKUP_NAME=${BACKUP_NAME}"
log "Debug: Copying from openhab/${OPENHAB_POD}:${LATEST_BACKUP} to ${TMP_DIR}/${BACKUP_NAME}"
kubectl cp "openhab/${OPENHAB_POD}:${LATEST_BACKUP}" "${TMP_DIR}/${BACKUP_NAME}" || {
    log "Failed to copy backup from pod. Check if backup was created successfully."
    rm -rf "${TMP_DIR}"
    exit 1
}
log "Debug: Contents of ${TMP_DIR}:"
ls -la "${TMP_DIR}"

log "[STEP] Creating backup directory and cleaning up old backups on NAS..."
export SSHPASS="${NAS_PASS}"
# Add timeout and verbose output for SSH
if ! timeout 60 sshpass -e ssh -vvv -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "mkdir -p '${NAS_PATH}' && find '${NAS_PATH}' -name 'openhab-backup-*.zip' -type f -mtime +5 -delete"; then
    log "Failed to create backup directory or cleanup old backups on NAS (exit code $?)"
    rm -rf "${TMP_DIR}"
    exit 1
fi

log "[STEP] Creating SSH config for port 4711..."
SSH_CONFIG_DIR="/root/.ssh"
SSH_CONFIG_FILE="${SSH_CONFIG_DIR}/config"
mkdir -p "${SSH_CONFIG_DIR}"
chmod 700 "${SSH_CONFIG_DIR}"
cat > "${SSH_CONFIG_FILE}" << EOF
Host ${NAS_HOST}
    Port 4711
EOF
log "Debug: Running command: chmod 600 \"${SSH_CONFIG_FILE}\""
chmod 600 "${SSH_CONFIG_FILE}"
log "Debug: SSH config created at ${SSH_CONFIG_FILE}"
ls -la "${SSH_CONFIG_FILE}"
cat "${SSH_CONFIG_FILE}"

log "[STEP] Copying backup to NAS via SCP..."
log "Debug: Using sshpass version: $(sshpass -V 2>&1)"
log "Debug: Command variables: TMP_DIR=${TMP_DIR}, BACKUP_NAME=${BACKUP_NAME}, NAS_USER=${NAS_USER}, NAS_HOST=${NAS_HOST}, NAS_PATH=${NAS_PATH}"
log "Debug: Full SCP command: sshpass -e scp -rv -O -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -F ${SSH_CONFIG_FILE} \"${TMP_DIR}/${BACKUP_NAME}\" ${NAS_USER}@${NAS_HOST}:${NAS_PATH}"
export SSHPASS="${NAS_PASS}"
SCP_LOG=$(mktemp)
if ! timeout 300 sshpass -e scp -rv -O -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -F "${SSH_CONFIG_FILE}" "${TMP_DIR}/${BACKUP_NAME}" ${NAS_USER}@${NAS_HOST}:${NAS_PATH} 2>&1 | tee "$SCP_LOG"; then
    log "Failed to copy backup to NAS (exit code $?). SCP output:"
    cat "$SCP_LOG"
    log "Debug: Testing SSH connection..."
    sshpass -e ssh -v -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "ls -la \"${NAS_PATH}\""
    rm -rf "${TMP_DIR}"
    rm -f "$SCP_LOG"
    exit 1
else
    log "Backup file successfully transferred to NAS. SCP output:"
    cat "$SCP_LOG"
fi
rm -f "$SCP_LOG"
log "Debug: Contents of ${TMP_DIR}:"
ls -la "${TMP_DIR}"
# Ensure all logs are flushed to Loki before pod exit to prevent missing final log lines
sync
sleep 5

log "[STEP] Cleaning up temporary directory..."
log "Debug: Running command: rm -rf \"${TMP_DIR}\""
rm -rf "${TMP_DIR}"

# Always clean up old backups in pod (keep only 5 most recent), even if NAS transfer fails
log "[STEP] Cleaning up old backups in pod (keep only 5 most recent)..."
log "Debug: Running command: kubectl exec -n openhab ${OPENHAB_POD} -- bash -c 'cd /openhab/userdata/backup && ls -t *.zip | tail -n +6 | xargs -r rm --'"
start_time=$(date +%s)
kubectl exec -n openhab ${OPENHAB_POD} -- bash -c 'cd /openhab/userdata/backup && ls -t *.zip | tail -n +6 | xargs -r rm --' || log "Warning: Post-backup cleanup in pod failed"
end_time=$(date +%s)
log "Debug: Command took $(($end_time - $start_time)) seconds to complete"

log "[STEP] Cleaning up old backups on NAS (keep only 5 most recent)..."
log "Debug: Running command: timeout 60 sshpass -e ssh -o StrictHostKeyChecking=no -p 4711 \"${NAS_USER}@${NAS_HOST}\" \"cd '${NAS_PATH}' && ls -t *.zip | tail -n +6 | xargs -r rm --\""
start_time=$(date +%s)
if ! timeout 60 sshpass -e ssh -o StrictHostKeyChecking=no -p 4711 "${NAS_USER}@${NAS_HOST}" "cd '${NAS_PATH}' && ls -t *.zip | tail -n +6 | xargs -r rm --"; then
    log "Warning: Failed to clean up old backups on NAS"
    # Don't exit with error as the backup was successful
fi

log "Backup successfully copied to NAS: ${NAS_PATH}/${BACKUP_NAME}.zip"
