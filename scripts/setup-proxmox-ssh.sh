#!/bin/bash

# Script to add SSH key to Proxmox server
# This will prompt for your Proxmox root password

# Check if IP was provided as argument
if [ -z "$1" ]; then
    echo "Usage: $0 <proxmox-ip>"
    echo "Example: $0 10.0.0.100"
    exit 1
fi

PROXMOX_IP="$1"

# Find SSH public key (try multiple key types)
SSH_KEY=""
for key_file in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
    if [ -f "$key_file" ]; then
        SSH_KEY=$(cat "$key_file")
        break
    fi
done

if [ -z "$SSH_KEY" ]; then
    echo "Error: No SSH public key found in ~/.ssh/"
    echo "Generate one with: ssh-keygen -t ed25519"
    exit 1
fi

echo "Adding SSH key to Proxmox server at ${PROXMOX_IP}"
echo "You will be prompted for the root password..."
echo ""

# Add SSH key to Proxmox
ssh root@${PROXMOX_IP} "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${SSH_KEY}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

if [ $? -eq 0 ]; then
    echo ""
    echo "SSH key added successfully!"
    echo "Testing connection..."
    ssh -o BatchMode=yes root@${PROXMOX_IP} "echo 'Connection successful!'"
else
    echo "Failed to add SSH key"
    exit 1
fi
