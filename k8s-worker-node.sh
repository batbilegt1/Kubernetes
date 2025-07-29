#!/bin/bash

set -e

# === CONFIGURATION ===
# You MUST set these values before running
export K8S_VERSION=v1.29.12         # Must match control plane version
export MASTER_IP=192.168.122.61         # Replace with your master IP or DNS name
export MASTER_NODE_NAME=vm5         # Replace with your master node name
export JOIN_TOKEN=jsbubi.jtf3b9g822qr0osm  # Replace with actual join token
export CA_CERT_HASH=sha256:4c0de2ed5fc525c418e3cd17b943f33fcda3e3ae8fe0585e4494b89f9587c92f # Replace with real hash

# === Internal ===
export JOIN_COMMAND="kubeadm join ${MASTER_IP}:6443 --token ${JOIN_TOKEN} --discovery-token-ca-cert-hash ${CA_CERT_HASH} --cri-socket unix:///var/run/cri-dockerd.sock"

# === Validation ===
if [[ $MASTER_IP == *"<"* || $JOIN_TOKEN == *"<"* || $CA_CERT_HASH == *"<"* ]]; then
  echo "[ERROR] Please replace MASTER_IP, JOIN_TOKEN, and CA_CERT_HASH with actual values."
  exit 1
fi

echo "[INFO] Joining Kubernetes cluster at $MASTER_IP with Kubernetes version $K8S_VERSION..."

### Disable swap
echo "[INFO] Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

### Load kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

### Apply sysctl settings
cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

### Install dependencies
echo "[INFO] Installing dependencies..."
sudo apt update
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release software-properties-common

sudo apt install unbound

### Install Docker
echo "[INFO] Installing Docker..."
sudo apt install -y docker.io
sudo systemctl enable --now docker

### Install cri-dockerd
echo "[INFO] Installing cri-dockerd..."
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.16/cri-dockerd_0.3.16.3-0.ubuntu-jammy_amd64.deb
sudo dpkg -i cri-dockerd_0.3.16.3-0.ubuntu-jammy_amd64.deb
sudo systemctl daemon-reload
sudo systemctl enable --now cri-docker

### Add Kubernetes APT repository
echo "[INFO] Adding Kubernetes apt repo..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION%.*}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION%.*}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm
sudo systemctl enable kubelet

### Pull required Kubernetes images
echo "[INFO] Pulling Kubernetes images..."
sudo kubeadm config images pull --cri-socket unix:///var/run/cri-dockerd.sock --kubernetes-version $K8S_VERSION

echo "[INFO] Adding master node entry to /etc/hosts..."
echo "${MASTER_IP} ${MASTER_NODE_NAME}" | sudo tee -a /etc/hosts

### Join the cluster
echo "[INFO] Running join command..."
sudo $JOIN_COMMAND

echo "[SUCCESS] Worker node successfully joined the cluster."
