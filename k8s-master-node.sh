#!/bin/bash

set -e  # Exit on any error

# === CONFIGURATION ===
# Use a fixed version (recommended for stability)
export K8S_VERSION=v1.29.12
# Or uncomment this to use the latest stable version automatically:
# export K8S_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)

echo "[INFO] Using Kubernetes version: $K8S_VERSION"

### Add helpful aliases
echo "export KUBECONFIG=\$HOME/.kube/config" >> ~/.bashrc
echo "alias k='kubectl'" >> ~/.bashrc
echo "alias kg='kubectl get'" >> ~/.bashrc
echo "alias kgn='kubectl get node'" >> ~/.bashrc
echo "alias kd='kubectl describe'" >> ~/.bashrc
echo "alias kl='kubectl logs -f'" >> ~/.bashrc
echo "alias kgpa='kubectl get pods --all-namespaces'" >> ~/.bashrc

### Disable Swap
echo "[INFO] Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

### Load required kernel modules
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
sudo apt install python3-netaddr -y

### Install Docker
echo "[INFO] Installing Docker..."
sudo apt install -y docker.io
sudo systemctl enable --now docker

### Install cri-dockerd
echo "[INFO] Installing cri-dockerd..."
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.16/cri-dockerd_0.3.16.3-0.ubuntu-jammy_amd64.deb
sudo dpkg -i cri-dockerd_0.3.16.3-0.ubuntu-jammy_amd64.deb

# Enable and start cri-dockerd
sudo systemctl daemon-reload
sudo systemctl enable --now cri-docker

### Add Kubernetes APT repository
echo "[INFO] Adding Kubernetes apt repo..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION%.*}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION%.*}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo systemctl enable kubelet

### Pull Kubernetes images
echo "[INFO] Pulling Kubernetes images..."
sudo kubeadm config images pull --cri-socket unix:///var/run/cri-dockerd.sock --kubernetes-version $K8S_VERSION

### Set static DNS (persistent way)
echo "[INFO] Setting static DNS..."
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nDNS=8.8.8.8\nFallbackDNS=1.1.1.1" | sudo tee /etc/systemd/resolved.conf.d/dns.conf
sudo systemctl restart systemd-resolved

### Update /etc/hosts
echo "[INFO] Updating /etc/hosts..."
MYIP=$(hostname -I | awk '{print $1}')
echo "$MYIP $(hostname)" | sudo tee -a /etc/hosts

### Initialize Kubernetes Control Plane
echo "[INFO] Initializing Kubernetes control plane..."
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --upload-certs \
  --kubernetes-version=$K8S_VERSION \
  --control-plane-endpoint=$(hostname) \
  --cri-socket unix:///var/run/cri-dockerd.sock

### Configure kubectl
echo "[INFO] Configuring kubectl for user..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
chmod 600 $HOME/.kube/config

### Apply Calico CNI
echo "[INFO] Installing Calico CNI..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

### Print join command
echo "[INFO] Save this join command to add worker nodes:"
sudo kubeadm token create --print-join-command --ttl 0

### Verify
echo "[INFO] Kubernetes API server version:"
curl -sk https://localhost:6443/version | jq || curl -sk https://localhost:6443/version

echo "[SUCCESS] Kubernetes master setup complete. Run 'kubectl get nodes' to verify."
