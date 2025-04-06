#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Ceph Monitor Migration Script${NC}"
echo -e "${YELLOW}This script will migrate Ceph monitors from local-path to rook-ceph-block storage${NC}"
echo -e "${YELLOW}IMPORTANT: Run this script one monitor at a time and verify cluster health between runs${NC}"
echo

if [ -z "$1" ]; then
  echo -e "${RED}Error: Monitor ID (m, n, or o) is required as the first argument${NC}"
  echo "Usage: $0 <monitor-id>"
  echo "Example: $0 m"
  exit 1
fi

MONITOR_ID=$1
NAMESPACE="rook-ceph"
MONITOR_NAME="rook-ceph-mon-${MONITOR_ID}"
NEW_PVC_NAME="${MONITOR_NAME}-ceph"
NEW_PVC_SIZE="25Gi"

echo -e "${GREEN}Step 1: Checking Ceph cluster health before migration${NC}"
CLUSTER_STATUS=$(kubectl -n $NAMESPACE get cephclusters rook-ceph -o jsonpath='{.status.phase}')
if [ "$CLUSTER_STATUS" != "Ready" ]; then
  echo -e "${RED}Error: Ceph cluster is not in Ready state. Current state: $CLUSTER_STATUS${NC}"
  echo "Please ensure the cluster is healthy before proceeding"
  exit 1
fi

echo -e "${GREEN}Step 2: Creating new PVC with rook-ceph-block storage class${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NEW_PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${NEW_PVC_SIZE}
  storageClassName: rook-ceph-block
EOF

echo -e "${GREEN}Step 3: Waiting for new PVC to be bound${NC}"
kubectl -n $NAMESPACE wait --for=condition=Bound pvc/${NEW_PVC_NAME} --timeout=60s

echo -e "${GREEN}Step 4: Scaling down the monitor deployment${NC}"
kubectl -n $NAMESPACE scale deployment ${MONITOR_NAME} --replicas=0

echo -e "${GREEN}Step 5: Waiting for monitor pod to terminate${NC}"
while kubectl -n $NAMESPACE get pods -l mon=${MONITOR_ID} 2>/dev/null | grep -q Running; do
  echo "Waiting for monitor pod to terminate..."
  sleep 5
done

echo -e "${GREEN}Step 6: Copying data from old PVC to new PVC${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${MONITOR_NAME}-data-mover
  namespace: ${NAMESPACE}
spec:
  containers:
  - name: data-mover
    image: busybox
    command: ["sh", "-c", "cp -av /source/* /destination/ && echo 'Data migration completed successfully'"]
    volumeMounts:
    - name: source-vol
      mountPath: /source
    - name: destination-vol
      mountPath: /destination
  volumes:
  - name: source-vol
    persistentVolumeClaim:
      claimName: ${MONITOR_NAME}
  - name: destination-vol
    persistentVolumeClaim:
      claimName: ${NEW_PVC_NAME}
  restartPolicy: Never
EOF

echo -e "${GREEN}Step 7: Waiting for data migration to complete${NC}"
kubectl -n $NAMESPACE wait --for=condition=complete job/${MONITOR_NAME}-data-mover --timeout=300s

echo -e "${GREEN}Step 8: Patching the monitor deployment to use the new PVC${NC}"
kubectl -n $NAMESPACE patch deployment ${MONITOR_NAME} --type=json -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/volumes/0/persistentVolumeClaim/claimName\", \"value\": \"${NEW_PVC_NAME}\"}]"

echo -e "${GREEN}Step 9: Scaling up the monitor deployment${NC}"
kubectl -n $NAMESPACE scale deployment ${MONITOR_NAME} --replicas=1

echo -e "${GREEN}Step 10: Waiting for monitor pod to be ready${NC}"
kubectl -n $NAMESPACE wait --for=condition=ready pod -l mon=${MONITOR_ID} --timeout=300s

echo -e "${GREEN}Step 11: Verifying Ceph cluster health${NC}"
sleep 30
CLUSTER_STATUS=$(kubectl -n $NAMESPACE get cephclusters rook-ceph -o jsonpath='{.status.phase}')
CLUSTER_HEALTH=$(kubectl -n $NAMESPACE get cephclusters rook-ceph -o jsonpath='{.status.ceph.health}')

echo -e "${GREEN}Migration completed for monitor ${MONITOR_ID}${NC}"
echo "Cluster status: $CLUSTER_STATUS"
echo "Cluster health: $CLUSTER_HEALTH"
echo
echo -e "${YELLOW}IMPORTANT: Wait for the cluster to stabilize before migrating the next monitor${NC}"
echo -e "${YELLOW}You can delete the old PVC after confirming cluster stability:${NC}"
echo "kubectl -n $NAMESPACE delete pvc ${MONITOR_NAME}"
echo
echo -e "${YELLOW}You can delete the data-mover pod after confirming successful migration:${NC}"
echo "kubectl -n $NAMESPACE delete pod ${MONITOR_NAME}-data-mover"
