#!/bin/bash

# Get the Ceph manager pod name
MGR_POD=$(kubectl -n rook-ceph get pod -l app=rook-ceph-mgr -o jsonpath='{.items[0].metadata.name}')

if [ -z "$MGR_POD" ]; then
  echo "Error: Could not find Ceph mgr pod"
  exit 1
fi

echo "Found mgr pod: $MGR_POD"

# Create a temporary file with the Ceph command
cat > /tmp/set-password.sh << 'EOF'
#!/bin/bash
ceph dashboard ac-user-set-password admin Admin123! --force-password
EOF

# Copy the script to the pod
kubectl -n rook-ceph cp /tmp/set-password.sh $MGR_POD:/tmp/set-password.sh

# Make the script executable and run it
kubectl -n rook-ceph exec $MGR_POD -- bash -c "chmod +x /tmp/set-password.sh && /tmp/set-password.sh"

# Clean up
rm /tmp/set-password.sh
kubectl -n rook-ceph exec $MGR_POD -- rm /tmp/set-password.sh

echo "Dashboard password set successfully"
