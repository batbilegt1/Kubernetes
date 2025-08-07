#!/bin/bash

set -euo pipefail

CLOUD_IMG_NAME="ubuntu-24.04-server-cloudimg-amd64.img"
CLOUD_IMG_URL="https://cloud-images.ubuntu.com/releases/24.04/release/$CLOUD_IMG_NAME"
IMAGE_DIR="/var/lib/libvirt/images"
BASE_IMG="$IMAGE_DIR/$CLOUD_IMG_NAME"
VM_PREFIX="vm"
VM_COUNT=9
DISK_SIZE="100G"

# 1. Install required packages
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils genisoimage

# 2. Download cloud image if missing
if [ ! -f "$BASE_IMG" ]; then
  wget "$CLOUD_IMG_URL" -O "$CLOUD_IMG_NAME"
  sudo mv "$CLOUD_IMG_NAME" "$BASE_IMG"
fi

# 3. Ensure SSH key exists
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
  ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

# 4. Loop to create VMs
for i in $(seq 1 $VM_COUNT); do
  VM_NAME="${VM_PREFIX}${i}"
  VM_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
  CLOUD_INIT_DIR="/tmp/${VM_NAME}-cloudinit"
  CLOUD_INIT_ISO_TMP="/tmp/${VM_NAME}-seed.iso"
  CLOUD_INIT_ISO="${IMAGE_DIR}/${VM_NAME}-seed.iso"

  # Create VM disk with larger size
  sudo qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$VM_DISK" "$DISK_SIZE"

  # Create cloud-init config
  mkdir -p "$CLOUD_INIT_DIR"

  cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: ubuntu
    ssh-authorized-keys:
      - $PUB_KEY
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
disable_root: false
ssh_pwauth: false
EOF

  cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

  # Create ISO
  genisoimage -output "$CLOUD_INIT_ISO_TMP" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
  sudo mv "$CLOUD_INIT_ISO_TMP" "$CLOUD_INIT_ISO"
  rm -rf "$CLOUD_INIT_DIR"

  # Launch VM
  sudo virt-install \
    --name "$VM_NAME" \
    --ram 4096 \
    --vcpus 2 \
    --disk path="$VM_DISK",format=qcow2 \
    --disk path="$CLOUD_INIT_ISO",device=cdrom \
    --os-type linux \
    --os-variant ubuntu24.04 \
    --graphics none \
    --import \
    --network network=default \
    --noautoconsole
done

echo "✅ All $VM_COUNT VMs created with cloud-init and $DISK_SIZE disk size."
