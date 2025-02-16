#!/bin/sh

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PORT="4711"
NAS_PATH="/volume1/openhab_backups"

# Get the pod name
OPENHAB_POD=$(kubectl get pods -n openhab -l app.kubernetes.io/name=openhab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPENHAB_POD" ]; then
    echo "Error: Could not find OpenHAB pod"
    exit 1
fi
echo "Found OpenHAB pod: ${OPENHAB_POD}"

# Get NAS password from environment
if [ -z "$NAS_PASSWORD" ]; then
    echo "Error: NAS_PASSWORD environment variable not set"
    exit 1
fi
export SSHPASS="${NAS_PASSWORD}"

# Create temporary directory for the transfer
TMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TMP_DIR}"

# List available backups
echo "Available backups on NAS:"
sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -l ${NAS_PATH}"

# Ask for backup file name
echo -n "Enter the backup file name to restore (e.g., openhab-backup-20250216_205421.zip): "
read BACKUP_FILE

# Verify backup file exists
if ! sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "test -f ${NAS_PATH}/${BACKUP_FILE}"; then
    echo "Error: Backup file ${BACKUP_FILE} not found on NAS"
    rm -rf "${TMP_DIR}"
    exit 1
fi

# Copy backup from NAS to temporary directory
echo "Copying backup from NAS..."
sshpass -e scp -P ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/${BACKUP_FILE}" "${TMP_DIR}/"

# Stop OpenHAB process
echo "Stopping OpenHAB process..."
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/stop 2>/dev/null || true
sleep 5
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f openhab 2>/dev/null || true
sleep 2
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f java 2>/dev/null || true

echo "Waiting for OpenHAB process to stop..."
sleep 10

# Copy backup to pod
echo "Copying backup to pod..."
kubectl cp "${TMP_DIR}/${BACKUP_FILE}" "openhab/${OPENHAB_POD}:/openhab/${BACKUP_FILE}"

# Extract backup in pod
echo "Extracting backup in pod..."
kubectl exec -n openhab ${OPENHAB_POD} -- sh -c "cd /openhab && unzip -o ${BACKUP_FILE}"

# Clean up backup file in pod
echo "Cleaning up..."
kubectl exec -n openhab ${OPENHAB_POD} -- rm "/openhab/${BACKUP_FILE}"

# Clean up temporary directory
rm -rf "${TMP_DIR}"

# Start OpenHAB process
echo "Starting OpenHAB process..."
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/start

echo "Restore completed successfully!"
echo "OpenHAB process has been restarted with restored files."
echo "Note: It may take a few minutes for OpenHAB to fully initialize."
