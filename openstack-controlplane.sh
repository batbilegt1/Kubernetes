#!/bin/bash

# === USER CONFIGURATION ===
NODES=(
  "vm1 192.168.122.251"
  "vm2 192.168.122.181"
  "vm3 192.168.122.166"
  "vm4 192.168.122.27"
)
CONTROL_PLANE_HOSTNAME="vm1"
USER="ubuntu"
SSH_KEY="$HOME/.ssh/id_rsa"
PUB_KEY="${SSH_KEY}.pub"

# === Install Helm ===
sudo snap install helm --classic
helm repo add openstack-helm https://tarballs.opendev.org/openstack/openstack-helm
helm plugin install https://opendev.org/openstack/openstack-helm-plugin

# === Clone Required Repos ===
mkdir -p ~/osh && cd ~/osh
git clone https://opendev.org/openstack/openstack-helm.git
git clone https://opendev.org/zuul/zuul-jobs.git

# === Install Ansible ===
sudo apt update
sudo apt install -y python3-pip
pip install --user ansible

export ANSIBLE_ROLES_PATH=~/osh/openstack-helm/roles:~/osh/zuul-jobs/roles

# === Generate Dynamic Inventory ===
cat > ~/osh/inventory.yaml <<EOF
all:
  vars:
    ansible_user: $USER
    ansible_port: 22
    ansible_ssh_private_key_file: $SSH_KEY
    ansible_ssh_extra_args: -o StrictHostKeyChecking=no
    kubectl:
      user: $USER
      group: $USER
    docker_users:
      - $USER
    client_ssh_user: $USER
    cluster_ssh_user: $USER
    metallb_setup: true
    loopback_setup: true
    loopback_device: /dev/loop100
    loopback_image: /var/lib/openstack-helm/ceph-loop.img
    loopback_image_size: 12G
  children:
    primary:
      hosts:
        $CONTROL_PLANE_HOSTNAME:
          ansible_host: $(for node in "${NODES[@]}"; do
              [[ "$(echo $node | awk '{print $1}')" == "$CONTROL_PLANE_HOSTNAME" ]] && echo $node | awk '{print $2}'
          done)
    k8s_cluster:
      hosts:
$(for node in "${NODES[@]}"; do
    HOSTNAME=$(echo $node | awk '{print $1}')
    IP=$(echo $node | awk '{print $2}')
    echo "        $HOSTNAME:"
    echo "          ansible_host: $IP"
done)
    k8s_control_plane:
      hosts:
        $CONTROL_PLANE_HOSTNAME:
          ansible_host: $(for node in "${NODES[@]}"; do
              [[ "$(echo $node | awk '{print $1}')" == "$CONTROL_PLANE_HOSTNAME" ]] && echo $node | awk '{print $2}'
          done)
    k8s_nodes:
      hosts:
$(for node in "${NODES[@]}"; do
    HOSTNAME=$(echo $node | awk '{print $1}')
    IP=$(echo $node | awk '{print $2}')
    if [[ "$HOSTNAME" != "$CONTROL_PLANE_HOSTNAME" ]]; then
        echo "        $HOSTNAME:"
        echo "          ansible_host: $IP"
    fi
done)
EOF

# === Generate Ansible Playbook ===
cat > ~/osh/deploy-env.yaml <<EOF
---
- hosts: all
  become: true
  gather_facts: true
  roles:
    - ensure-python
    - ensure-pip
    - clear-firewall
    - deploy-env
EOF

# === Run the Ansible Playbook ===
cd ~/osh
ansible-playbook -i inventory.yaml deploy-env.yaml
