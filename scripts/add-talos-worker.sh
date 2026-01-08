#!/bin/bash

# Talos Worker Node Deployment Script for Proxmox
# This script deploys Talos Linux worker nodes to Proxmox and joins them to an existing cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TALOSCONFIG="${REPO_ROOT}/talosconfig"
WORKER_CONFIG="${REPO_ROOT}/worker.yaml"
TALOS_VERSION="${TALOS_VERSION:-v1.12.0}"  # Can be overridden with env var
ISO_FILENAME="metal-amd64.iso"              # Standard Talos ISO filename

# Check if worker.yaml exists
if [ ! -f "$WORKER_CONFIG" ]; then
    echo -e "${RED}Error: worker.yaml not found in ${REPO_ROOT}${NC}"
    echo "Please run 'talosctl gen config' first to generate worker configuration"
    exit 1
fi

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Talos worker nodes to Proxmox and join them to the cluster.

OPTIONS:
    -h, --help              Show this help message
    -n, --node-name         Name for the worker node (e.g., talos-worker-1)
    -i, --ip-address        IP address for the worker node (e.g., 192.168.1.164)
    -p, --proxmox-node      Proxmox node name (e.g., pve)
    -v, --vm-id             VM ID in Proxmox (e.g., 201)
    -m, --memory            Memory in MB (default: 2048)
    -c, --cores             CPU cores (default: 2)
    -d, --disk-size         Disk size in GB (default: 32)
    -s, --storage           Storage pool (default: local-lvm)
    -b, --bridge            Network bridge (default: vmbr0)
    --iso-storage           ISO storage location (default: local)
    --skip-vm-creation      Skip VM creation (only apply config to existing VM)

EXAMPLES:
    # Deploy a new worker with all options
    $0 -n talos-worker-1 -i 192.168.1.164 -p pve -v 201

    # Deploy with custom resources
    $0 -n talos-worker-2 -i 192.168.1.165 -p pve -v 202 -m 8192 -c 4 -d 50

    # Only apply config to existing VM
    $0 -i 192.168.1.164 --skip-vm-creation

EOF
}

# Default values
MEMORY=2048
CORES=2
DISK_SIZE=32
STORAGE="local-lvm"
BRIDGE="vmbr0"
ISO_STORAGE="local"
SKIP_VM_CREATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--node-name)
            NODE_NAME="$2"
            shift 2
            ;;
        -i|--ip-address)
            IP_ADDRESS="$2"
            shift 2
            ;;
        -p|--proxmox-node)
            PROXMOX_NODE="$2"
            shift 2
            ;;
        -v|--vm-id)
            VM_ID="$2"
            shift 2
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -c|--cores)
            CORES="$2"
            shift 2
            ;;
        -d|--disk-size)
            DISK_SIZE="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE="$2"
            shift 2
            ;;
        -b|--bridge)
            BRIDGE="$2"
            shift 2
            ;;
        --iso-storage)
            ISO_STORAGE="$2"
            shift 2
            ;;
        --skip-vm-creation)
            SKIP_VM_CREATION=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$IP_ADDRESS" ]; then
    log_error "IP address is required (-i or --ip-address)"
    usage
    exit 1
fi

if [ "$SKIP_VM_CREATION" = false ]; then
    if [ -z "$NODE_NAME" ] || [ -z "$PROXMOX_NODE" ] || [ -z "$VM_ID" ]; then
        log_error "Node name, Proxmox node, and VM ID are required for VM creation"
        usage
        exit 1
    fi
fi

# Check for talosctl
TALOSCTL_CMD=""
if command -v talosctl &> /dev/null; then
    TALOSCTL_CMD="talosctl"
elif [ -f "$HOME/bin/talosctl" ]; then
    TALOSCTL_CMD="$HOME/bin/talosctl"
else
    log_error "talosctl not found. Please install it first."
    exit 1
fi

log_info "Using talosctl: $TALOSCTL_CMD"

# Function to create VM in Proxmox
create_proxmox_vm() {
    log_info "Creating Talos worker VM in Proxmox..."

    log_info "Checking for Talos ISO..."

    # Check if ISO exists on Proxmox
    if ! ssh root@${PROXMOX_NODE} "test -f /var/lib/vz/template/iso/${ISO_FILENAME}"; then
        log_warn "Talos ISO not found at /var/lib/vz/template/iso/${ISO_FILENAME}"
        echo ""
        echo "  On your Proxmox node, run:"
        echo "  cd /var/lib/vz/template/iso"
        echo "  wget https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso"
        echo ""
        read -p "Press Enter once you've uploaded the ISO..."
    fi

    log_info "Creating VM ${VM_ID} (${NODE_NAME})..."

    # Create VM via SSH to Proxmox
    ssh root@${PROXMOX_NODE} "qm create ${VM_ID} \
        --name ${NODE_NAME} \
        --memory ${MEMORY} \
        --cores ${CORES} \
        --cpu x86-64-v2-AES \
        --sockets 1 \
        --numa 0 \
        --net0 virtio,bridge=${BRIDGE},firewall=1 \
        --scsihw virtio-scsi-single \
        --scsi0 ${STORAGE}:${DISK_SIZE},iothread=1 \
        --ide2 ${ISO_STORAGE}:iso/${ISO_FILENAME},media=cdrom \
        --boot 'order=scsi0;ide2;net0' \
        --ostype l26 && qm start ${VM_ID}"

    if [ $? -eq 0 ]; then
        log_info "VM ${VM_ID} created successfully"
    else
        log_error "Failed to create VM"
        exit 1
    fi

    log_warn "Waiting 30 seconds for VM to boot..."
    sleep 30
}

# Function to apply Talos configuration
apply_talos_config() {
    log_info "Applying Talos worker configuration to ${IP_ADDRESS}..."

    export TALOSCONFIG="${TALOSCONFIG}"

    $TALOSCTL_CMD apply-config \
        --insecure \
        --nodes ${IP_ADDRESS} \
        --file ${WORKER_CONFIG}

    if [ $? -eq 0 ]; then
        log_info "Configuration applied successfully"
    else
        log_error "Failed to apply configuration"
        exit 1
    fi

    log_warn "Node is rebooting and joining the cluster..."
    log_warn "This may take 2-3 minutes..."
    sleep 120
}

# Function to verify node joined cluster
verify_node() {
    log_info "Verifying node joined the cluster..."

    # Wait for node to appear in kubectl
    for i in {1..30}; do
        if kubectl get nodes | grep -q "${IP_ADDRESS}"; then
            log_info "Node successfully joined the cluster!"
            kubectl get nodes
            return 0
        fi
        echo -n "."
        sleep 10
    done

    log_warn "Node not showing in kubectl yet. Check with: kubectl get nodes"
    return 1
}

# Main execution
log_info "=== Talos Worker Node Deployment ==="
log_info "IP Address: ${IP_ADDRESS}"

if [ "$SKIP_VM_CREATION" = false ]; then
    log_info "Node Name: ${NODE_NAME}"
    log_info "Proxmox Node: ${PROXMOX_NODE}"
    log_info "VM ID: ${VM_ID}"
    log_info "Memory: ${MEMORY}MB"
    log_info "Cores: ${CORES}"
    log_info "Disk: ${DISK_SIZE}GB"
    echo ""

    read -p "Proceed with VM creation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Aborted by user"
        exit 0
    fi

    create_proxmox_vm
fi

log_info "Applying Talos configuration..."
apply_talos_config

log_info "Verifying cluster membership..."
verify_node

log_info "=== Deployment Complete ==="
log_info "Worker node ${IP_ADDRESS} has been added to the cluster"
log_info ""
log_info "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  $TALOSCTL_CMD -n ${IP_ADDRESS} dashboard"
