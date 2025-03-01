#!/bin/bash

# Apply the toolbox deployment
kubectl apply -f toolbox.yaml

# Wait for the toolbox pod to be ready
echo "Waiting for toolbox pod to be ready..."
sleep 10

# Get the toolbox pod name
TOOLS_POD=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')

if [ -z "$TOOLS_POD" ]; then
  echo "Error: Could not find toolbox pod"
  exit 1
fi

echo "Found toolbox pod: $TOOLS_POD"

# Wait for the pod to be fully ready
kubectl -n rook-ceph wait --for=condition=Ready pod/$TOOLS_POD --timeout=60s

# Set the dashboard password
echo "Setting dashboard password..."
kubectl -n rook-ceph exec $TOOLS_POD -- ceph dashboard ac-user-set-password admin Admin123! --force-password

echo "Dashboard password set successfully"
