#!/bin/bash

set -euo pipefail

ISO_NAME="ubuntu-22.04.5-live-server-amd64.iso"
ISO_PATH="/var/lib/libvirt/images/$ISO_NAME"
BASE_DISK="/var/lib/libvirt/images/ubuntu-vm-base.qcow2"
VM_PREFIX="vm-0"
VM_COUNT=9
IMAGE_DIR="/var/lib/libvirt/images"

# 1. Install required packages
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils genisoimage

# 2. Download Ubuntu ISO if missing
if [ ! -f "$ISO_PATH" ]; then
  wget https://releases.ubuntu.com/jammy/$ISO_NAME -O "$ISO_NAME"
  sudo mv "$ISO_NAME" "$ISO_PATH"
fi

# 3. Create base disk if missing
if [ ! -f "$BASE_DISK" ]; then
  sudo qemu-img create -f qcow2 "$BASE_DISK" 100G
fi

# 4. Ensure SSH key exists
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
  ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

# 5. Loop to create VMs
for i in $(seq 1 $VM_COUNT); do
  VM_NAME="${VM_PREFIX}${i}"
  VM_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
  CLOUD_INIT_DIR="/tmp/${VM_NAME}-cloudinit"
  CLOUD_INIT_ISO_TMP="/tmp/${VM_NAME}-seed.iso"
  CLOUD_INIT_ISO="${IMAGE_DIR}/${VM_NAME}-seed.iso"

  # Create VM disk by copying base
  sudo cp "$BASE_DISK" "$VM_DISK"

  # Create cloud-init user-data and meta-data
  mkdir -p "$CLOUD_INIT_DIR"

  cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
users:
  - name: ubuntu
    ssh-authorized-keys:
      - $PUB_KEY
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
ssh_pwauth: false
disable_root: false
EOF

  cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

  # Create cloud-init ISO in /tmp
  genisoimage -output "$CLOUD_INIT_ISO_TMP" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"

  # Move ISO to /var/lib/libvirt/images with sudo
  sudo mv "$CLOUD_INIT_ISO_TMP" "$CLOUD_INIT_ISO"

  # Clean up temp files
  rm -rf "$CLOUD_INIT_DIR"

  # Create VM with cloud-init ISO attached
  sudo virt-install \
    --name "$VM_NAME" \
    --ram 4096 \
    --vcpus 2 \
    --disk path="$VM_DISK",format=qcow2 \
    --disk path="$CLOUD_INIT_ISO",device=cdrom \
    --os-type linux \
    --os-variant ubuntu22.04 \
    --graphics none \
    --cdrom "$ISO_PATH" \
    --network network=default \
    --noautoconsole
done

echo "✅ All VMs created with passwordless SSH using your SSH key."
