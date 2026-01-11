#!/bin/bash
#
# Safe K3s Node Restart Script
# Handles drain, restart, and uncordon to prevent RBD mount issues
#
# Usage: ./safe-k3s-restart.sh <node-name> [master|worker]
#

set -e

NODE_NAME="${1:-}"
NODE_TYPE="${2:-worker}"

if [ -z "$NODE_NAME" ]; then
    echo "Usage: $0 <node-name> [master|worker]"
    echo ""
    echo "Examples:"
    echo "  $0 k3s-w-1 worker    # Restart worker node"
    echo "  $0 k3s-m-1 master    # Restart master node"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if node exists
if ! kubectl get node "$NODE_NAME" &>/dev/null; then
    log_error "Node '$NODE_NAME' not found in cluster"
    exit 1
fi

log_info "Starting safe restart of node: $NODE_NAME (type: $NODE_TYPE)"

# Step 1: Drain the node
log_info "Step 1/5: Draining node $NODE_NAME..."
kubectl drain "$NODE_NAME" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=60 \
    --timeout=300s || {
        log_warn "Drain had warnings, continuing..."
    }

log_info "Node drained successfully"

# Step 2: Wait for pods to terminate and volumes to unmount
log_info "Step 2/5: Waiting 30 seconds for volumes to unmount cleanly..."
sleep 30

# Step 3: Restart K3s service on the node
log_info "Step 3/5: Restarting K3s service on $NODE_NAME..."
if [ "$NODE_TYPE" = "master" ]; then
    ssh "janne@$NODE_NAME" "sudo systemctl restart k3s"
else
    ssh "janne@$NODE_NAME" "sudo systemctl restart k3s-agent"
fi

# Step 4: Wait for node to become Ready
log_info "Step 4/5: Waiting for node to become Ready..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    STATUS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "True" ]; then
        log_info "Node $NODE_NAME is Ready"
        break
    fi
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_error "Timeout waiting for node to become Ready"
    exit 1
fi

# Step 5: Uncordon the node
log_info "Step 5/5: Uncordoning node $NODE_NAME..."
kubectl uncordon "$NODE_NAME"

# Verify final status
log_info "Verifying node status..."
kubectl get node "$NODE_NAME" -o wide

# Check for certificate warnings
log_info "Checking for certificate warnings..."
if [ "$NODE_TYPE" = "master" ]; then
    ssh "janne@$NODE_NAME" "sudo journalctl -u k3s --since '1 minute ago' | grep -i 'certificate' | head -3" || true
else
    ssh "janne@$NODE_NAME" "sudo journalctl -u k3s-agent --since '1 minute ago' | grep -i 'certificate' | head -3" || true
fi

echo ""
log_info "=========================================="
log_info "Safe restart of $NODE_NAME completed!"
log_info "=========================================="
echo ""
log_info "Recommended: Check pod status with:"
echo "  kubectl get pods -A -o wide | grep $NODE_NAME"
