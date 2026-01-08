#!/bin/bash

# Simple Talos Worker Node Addition Script
# Use this if you've already created the Talos VM manually in Proxmox

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Add Talos Worker Node ===${NC}"
echo ""

# Get worker IP
read -p "Enter the worker node IP address: " WORKER_IP

if [ -z "$WORKER_IP" ]; then
    echo "IP address is required"
    exit 1
fi

# Set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOSCONFIG="${REPO_ROOT}/talosconfig"
WORKER_CONFIG="${REPO_ROOT}/worker.yaml"

# Find talosctl
TALOSCTL_CMD=""
if command -v talosctl &> /dev/null; then
    TALOSCTL_CMD="talosctl"
elif [ -f "$HOME/bin/talosctl" ]; then
    TALOSCTL_CMD="$HOME/bin/talosctl"
else
    echo "Error: talosctl not found"
    exit 1
fi

# Check if worker.yaml exists
if [ ! -f "$WORKER_CONFIG" ]; then
    echo "Error: worker.yaml not found"
    echo "Generate it first with: talosctl gen config <cluster-name> https://<control-plane-ip>:6443"
    exit 1
fi

echo -e "${GREEN}Step 1: Applying worker configuration to ${WORKER_IP}${NC}"
export TALOSCONFIG="${TALOSCONFIG}"

$TALOSCTL_CMD apply-config \
    --insecure \
    --nodes ${WORKER_IP} \
    --file ${WORKER_CONFIG}

echo ""
echo -e "${YELLOW}Step 2: Waiting for node to initialize (120 seconds)...${NC}"
sleep 120

echo ""
echo -e "${GREEN}Step 3: Checking cluster nodes${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}=== Complete ===${NC}"
echo "Worker node ${WORKER_IP} should now be part of your cluster"
echo ""
echo "Verify with:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
