#!/bin/bash

set -euo pipefail

VM_PREFIX="bmh-vm-0"
VM_COUNT=9
IMAGE_DIR="/var/lib/libvirt/images"
SEED_IMG="${IMAGE_DIR}/seed.img"

echo "🧹 Cleaning up VMs and images..."

for i in $(seq 1 $VM_COUNT); do
  VM_NAME="${VM_PREFIX}${i}"

  # Destroy VM if running
  if virsh domstate "$VM_NAME" &>/dev/null; then
    STATE=$(virsh domstate "$VM_NAME")
    if [ "$STATE" = "running" ]; then
      echo "⏹️ Stopping $VM_NAME"
      sudo virsh destroy "$VM_NAME"
    fi

    # Undefine VM (remove config)
    echo "❌ Undefining $VM_NAME"
    sudo virsh undefine "$VM_NAME" --remove-all-storage
  else
    echo "⚠️ VM $VM_NAME does not exist, skipping."
  fi

  # Remove disk file if exists
  DISK_PATH="${IMAGE_DIR}/${VM_NAME}.qcow2"
  if [ -f "$DISK_PATH" ]; then
    echo "🗑️ Removing disk $DISK_PATH"
    sudo rm -f "$DISK_PATH"
  fi
done

# Remove cloud-init seed image if exists
if [ -f "$SEED_IMG" ]; then
  echo "🗑️ Removing cloud-init seed image $SEED_IMG"
  sudo rm -f "$SEED_IMG"
fi

echo "✅ Cleanup complete."
