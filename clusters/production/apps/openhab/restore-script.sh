#!/bin/sh

# Function to perform kubectl cp with retries
kubectl_cp_with_retry() {
    local src="$1"
    local dst="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if kubectl cp "$src" "$dst" 2>/dev/null; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "Retry $retry_count/$max_retries: Failed to copy, waiting 10 seconds..."
            sleep 10
        fi
    done
    
    return 1
}

# NAS details
NAS_USER="jannenasadm"
NAS_HOST="192.168.50.25"
NAS_PORT="4711"
# Get the pod name
OPENHAB_POD=$(kubectl get pods -n openhab -l app.kubernetes.io/name=openhab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$OPENHAB_POD" ]; then
    echo "Error: Could not find OpenHAB pod"
    exit 1
fi
echo "Found OpenHAB pod: ${OPENHAB_POD}"
NAS_BASE_DIR="/volume1/openhab-production"

# Get NAS password from environment
NAS_PASS="${NAS_PASSWORD}"
export SSHPASS="${NAS_PASS}"

# Create temporary directory for the transfer
TMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TMP_DIR}"

# Test SSH connection and get PVC directory names
echo "Testing SSH connection to NAS and getting PVC directories..."
if ! sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -la \"${NAS_BASE_DIR}\""; then
    echo "Error: Cannot access source directory on NAS"
    rm -rf "${TMP_DIR}"
    exit 1
fi

# Get PVC directory names
echo "Finding PVC directories..."
CONF_DIR=$(sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -d ${NAS_BASE_DIR}/default-openhab-production-conf-claim-pvc-*" 2>/dev/null)
USERDATA_DIR=$(sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -d ${NAS_BASE_DIR}/default-openhab-production-userdata-claim-pvc-*" 2>/dev/null)
ADDONS_DIR=$(sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -d ${NAS_BASE_DIR}/default-openhab-production-addons-claim-pvc-*" 2>/dev/null)
KARAF_DIR=$(sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -d ${NAS_BASE_DIR}/default-openhab-production-karaf-claim-pvc-*" 2>/dev/null)

# Debug output
echo "Found directories:"
echo "CONF_DIR: ${CONF_DIR}"
echo "USERDATA_DIR: ${USERDATA_DIR}"
echo "ADDONS_DIR: ${ADDONS_DIR}"
echo "KARAF_DIR: ${KARAF_DIR}"

# Verify directories exist
echo "Verifying directories on NAS..."
sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -la ${CONF_DIR} ${USERDATA_DIR} ${ADDONS_DIR} ${KARAF_DIR}" 2>&1

# Function to copy directory from NAS to pod
copy_directory() {
    local src_dir="$1"
    local pod_path="$2"
    local dir_name="$(basename "${pod_path}")"
    
    if [ -z "$src_dir" ]; then
        echo "Warning: Source directory for ${dir_name} not found, skipping..."
        return 0
    fi
    
    echo "Copying ${dir_name} from NAS..."
    
    # Debug: Show source directory contents
    echo "Checking contents of source directory: ${src_dir}"
    sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no "${NAS_USER}@${NAS_HOST}" "ls -la \"${src_dir}\"" || {
        echo "Error: Cannot list contents of ${src_dir}"
        return 1
    }

    # Create target directory
    mkdir -p "${TMP_DIR}/${dir_name}"

    # Copy from NAS to temporary directory using rsync
    echo "Copying from ${src_dir} to ${TMP_DIR}/${dir_name}"
    SSHPASS="${NAS_PASS}" rsync -av -e "sshpass -e ssh -p ${NAS_PORT} -o StrictHostKeyChecking=no" "${NAS_USER}@${NAS_HOST}:${src_dir}/" "${TMP_DIR}/${dir_name}/" 2>&1
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy ${dir_name} from NAS"
        return 1
    fi
    
    # Copy from temporary directory to pod
    echo "Copying ${dir_name} to OpenHAB pod..."
    kubectl cp "${TMP_DIR}/${dir_name}/" "openhab/${OPENHAB_POD}:${pod_path}/"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy ${dir_name} to pod"
        return 1
    fi
    
    return 0
}

# Stop the OpenHAB process inside the pod
echo "Stopping OpenHAB process..."

# Try multiple methods to stop OpenHAB
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/stop 2>/dev/null || true
sleep 5
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f openhab 2>/dev/null || true
sleep 2
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f java 2>/dev/null || true

echo "Waiting for OpenHAB process to stop..."
sleep 10  # Give OpenHAB time to shutdown gracefully

# Verify process is stopped
if kubectl exec -n openhab ${OPENHAB_POD} -- pgrep -f openhab > /dev/null 2>&1; then
    echo "Warning: OpenHAB process still running, will proceed anyway"
fi

# Wait a moment for the process to stop
sleep 5

# Verify process is stopped
if kubectl exec -n openhab ${OPENHAB_POD} -- pgrep -f openhab > /dev/null; then
    echo "Error: Failed to stop OpenHAB process"
    exit 1
fi

echo "OpenHAB process stopped, proceeding with restore..."

echo "Waiting for pod to be ready..."
while ! kubectl get pod -n openhab ${OPENHAB_POD} >/dev/null 2>&1; do
    echo "Waiting for pod to be created..."
    sleep 5
done

# Wait for pod to be ready
echo "Waiting for pod container to be running..."
kubectl wait --for=condition=ready pod -n openhab ${OPENHAB_POD} --timeout=300s

# Stop OpenHAB process inside the pod
echo "Stopping OpenHAB process..."
# Try multiple methods to stop OpenHAB
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/stop || true
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f openhab || true
kubectl exec -n openhab ${OPENHAB_POD} -- pkill -f java || true

echo "Waiting for OpenHAB process to stop..."
sleep 30  # Give OpenHAB time to shutdown gracefully

# Verify process is stopped
if kubectl exec -n openhab ${OPENHAB_POD} -- pgrep -f openhab > /dev/null; then
    echo "Warning: OpenHAB process still running, will proceed anyway"
fi

# Copy each directory
echo "Copying files to pod..."
copy_directory "${CONF_DIR}" "/openhab/conf" || exit 1
copy_directory "${USERDATA_DIR}" "/openhab/userdata" || exit 1
copy_directory "${ADDONS_DIR}" "/openhab/addons" || exit 1
copy_directory "${KARAF_DIR}" "/openhab/.karaf" || exit 1

# Clean up
echo "Cleaning up temporary directory..."
rm -rf "${TMP_DIR}"

# Start OpenHAB process
echo "Starting OpenHAB process..."
kubectl exec -n openhab ${OPENHAB_POD} -- /openhab/runtime/bin/start

echo "Restore completed successfully!"
echo "OpenHAB process has been restarted with restored files."
echo "Note: It may take a few minutes for OpenHAB to fully initialize."
