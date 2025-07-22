#!/bin/bash

set -e

# 1. Install required packages
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils

# 2. Download ISO if not exists
ISO_NAME="ubuntu-22.04.5-live-server-amd64.iso"
ISO_PATH="/var/lib/libvirt/images/$ISO_NAME"
if [ ! -f "$ISO_PATH" ]; then
    wget https://releases.ubuntu.com/jammy/$ISO_NAME -O "$ISO_NAME"
    sudo mv "$ISO_NAME" "$ISO_PATH"
fi

# 3. Create base disk
BASE_DISK="/var/lib/libvirt/images/ubuntu-vm-base.qcow2"
if [ ! -f "$BASE_DISK" ]; then
    sudo qemu-img create -f qcow2 "$BASE_DISK" 100G
fi

# 4. Ensure SSH key exists
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "SSH key not found. Creating new key..."
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi
PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)

# 5. Create autoinstall seed image for passwordless login
mkdir -p seed
cat > seed/meta-data <<EOF
instance-id: ubuntu-autoinstall
local-hostname: ubuntu
EOF

cat > seed/user-data <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu
    username: ubuntu
    password: "\$6\$rounds=4096\$qwerty\$yXmqDdAv4KrGfJoU3tEw2.RhOZC8iRt4ZBQO4v3ubGnkgSkPpC/7lWY5RWr6sfmuw7Ym4zGeDUPL/t/FtTTvn1"
  ssh:
    install-server: true
    authorized-keys:
      - $PUB_KEY
EOF

cloud-localds seed.img seed/user-data seed/meta-data
sudo mv seed.img /var/lib/libvirt/images/seed.img

# 6. Create 9 VMs
for i in {1..9}; do
  VM_NAME="bmh-vm-0$i"
  VM_DISK="/var/lib/libvirt/images/${VM_NAME}.qcow2"

  echo "Creating disk and VM: $VM_NAME"
  sudo cp "$BASE_DISK" "$VM_DISK"

  sudo virt-install \
    --name "$VM_NAME" \
    --ram 8192 \
    --vcpus 4 \
    --disk path="$VM_DISK",size=100 \
    --disk path=/var/lib/libvirt/images/seed.img,device=cdrom \
    --os-type linux \
    --os-variant ubuntu22.04 \
    --graphics none \
    --cdrom "$ISO_PATH" \
    --network network=default \
    --noautoconsole
done

echo "✅ All 9 VMs created with SSH key injected. Passwordless login enabled."
