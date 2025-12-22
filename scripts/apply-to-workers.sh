#!/bin/bash
# Script to apply K3s configuration to all worker nodes

# List of worker node IPs - replace these with your actual worker node IPs
WORKER_NODES=(
  "192.168.50.237"  # k3s-w-1
  "192.168.50.115"  # k3s-w-2
  "192.168.50.108"  # k3s-w-3
)

# SSH user for connecting to nodes
SSH_USER="janne"  # Replace with your actual username on the worker nodes

# Path to the configuration script
CONFIG_SCRIPT="$(pwd)/apply-k3s-config.sh"

echo "Starting configuration of worker nodes..."
echo "Using configuration script: $CONFIG_SCRIPT"

# Process one node at a time
for NODE_IP in "${WORKER_NODES[@]}"; do
  echo "===================================="
  echo "Configuring worker node: $NODE_IP"
  
  # Copy the script to the worker node
  echo "Copying configuration script to $NODE_IP..."
  scp "$CONFIG_SCRIPT" "$SSH_USER@$NODE_IP:~/apply-k3s-config.sh"
  
  if [ $? -ne 0 ]; then
    echo "Failed to copy script to $NODE_IP. Skipping this node."
    continue
  fi
  
  # Execute the script on the worker node
  echo "Applying configuration on $NODE_IP..."
  ssh "$SSH_USER@$NODE_IP" "sudo bash ~/apply-k3s-config.sh"
  
  if [ $? -ne 0 ]; then
    echo "Failed to apply configuration on $NODE_IP."
  else
    echo "Successfully configured $NODE_IP."
  fi
  
  echo "Waiting 30 seconds before proceeding to the next node..."
  sleep 30
done

echo "===================================="
echo "Configuration of worker nodes completed."
echo "Please check your monitoring system to verify that the TargetDown alerts are resolved."
