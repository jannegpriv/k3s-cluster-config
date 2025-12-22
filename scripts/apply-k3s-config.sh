#!/bin/bash
# Script to apply K3s configuration for component monitoring

# Determine if this is a master or worker node
IS_MASTER=false
if [ -f /etc/rancher/k3s/k3s.yaml ] || [ -f /etc/rancher/k3s/config.yaml.d/master.yaml ]; then
  IS_MASTER=true
fi

# Create directory if it doesn't exist
sudo mkdir -p /etc/rancher/k3s

# Create or update the config file
echo "Applying K3s configuration..."
sudo tee /etc/rancher/k3s/config.yaml > /dev/null << 'EOF'
kube-proxy-arg:
  - "metrics-bind-address=0.0.0.0"
EOF

# Add control plane specific configs if this is a master node
if [ "$IS_MASTER" = true ]; then
  echo "Detected master node, adding control plane configurations..."
  sudo tee -a /etc/rancher/k3s/config.yaml > /dev/null << 'EOF'
kube-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-scheduler-arg:
  - "bind-address=0.0.0.0"
EOF
fi

echo "K3s configuration has been applied to /etc/rancher/k3s/config.yaml"
echo "Restarting K3s service..."

# Restart the K3s service
if [ "$IS_MASTER" = true ]; then
  echo "Restarting K3s server..."
  sudo systemctl restart k3s
else
  echo "Restarting K3s agent..."
  sudo systemctl restart k3s-agent
fi

echo "K3s service has been restarted"
echo "Waiting for K3s to be ready..."
sleep 10

# Check if K3s is running
if [ "$IS_MASTER" = true ] && sudo systemctl is-active k3s > /dev/null; then
  echo "K3s server is running successfully"
elif [ "$IS_MASTER" = false ] && sudo systemctl is-active k3s-agent > /dev/null; then
  echo "K3s agent is running successfully"
else
  echo "Warning: K3s service is not running. Please check the logs with 'sudo journalctl -u k3s' or 'sudo journalctl -u k3s-agent'"
fi
# Check if the metrics endpoints are accessible
echo "Checking if metrics endpoints are accessible..."

# Check kube-scheduler metrics
echo "Testing kube-scheduler metrics endpoint..."
if curl -s -k https://localhost:10259/metrics > /dev/null; then
  echo "✅ kube-scheduler metrics endpoint is accessible"
else
  echo "❌ kube-scheduler metrics endpoint is not accessible"
fi

# Check kube-controller-manager metrics
echo "Testing kube-controller-manager metrics endpoint..."
if curl -s -k https://localhost:10257/metrics > /dev/null; then
  echo "✅ kube-controller-manager metrics endpoint is accessible"
else
  echo "❌ kube-controller-manager metrics endpoint is not accessible"
fi

# Check kube-proxy metrics
echo "Testing kube-proxy metrics endpoint..."
if curl -s http://localhost:10249/metrics > /dev/null; then
  echo "✅ kube-proxy metrics endpoint is accessible"
else
  echo "❌ kube-proxy metrics endpoint is not accessible"
fi

echo "Configuration complete!"
