#!/bin/bash
# Run this on rk1-node4 (control node - this is where all ansible-playbook commands run from)

# Install Ansible plus the collections our playbooks depend on
# (docker_container/docker_compose, community.general.shutdown)
echo "Installing Ansible on rk1-node4..."
sudo apt update
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y \
    ansible \
    build-essential \
    python3 \
    python3-dev \
    python-is-python3 \
    python3-pip \
    python3-pymongo \
    python3-venv \
    gnuplot
ansible-galaxy collection install -r requirements.yml

# Create convenient, repeatable commands for Python data-injection scripts and
# the first YCSB test. ~/.bash_aliases is sourced by interactive Bash shells.
echo "Configuring Python and MongoDB aliases..."
touch ~/.bash_aliases
sed -i '/# rk1-ansible aliases begin/,/# rk1-ansible aliases end/d' ~/.bash_aliases
cat >> ~/.bash_aliases <<'EOF'
# rk1-ansible aliases begin
alias python='python3'
alias py='python3'
alias pip='python3 -m pip'
alias mongo-status="ssh rk1-node1 \"docker exec mongodb mongosh --quiet --eval 'rs.status().members.map(m => ({name:m.name, state:m.stateStr, health:m.health}))'\""
alias apb='ansible-playbook -i inventory.yml --vault-password-file vault_password_file'
# rk1-ansible aliases end
EOF

if ! grep -Fqx 'source ~/.bash_aliases' ~/.bashrc 2>/dev/null; then
    printf '\n# Load local shell aliases\nsource ~/.bash_aliases\n' >> ~/.bashrc
fi

# Validate the Ansible installation
echo "Validating Ansible installation..."
if ansible --version >/dev/null 2>&1; then
    echo "✅ Ansible installed: $(ansible --version | head -n1)"
else
    echo "❌ Ansible installation failed"
    exit 1
fi

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Copy SSH keys to all nodes (you'll need to enter passwords)
for node in rk1-node1 rk1-node2 rk1-node3 rk1-node4; do
    echo "Setting up SSH key for $node..."
    ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@$node
done

# Test SSH connectivity
echo "Testing SSH connections..."
for node in rk1-node1 rk1-node2 rk1-node3; do
    ssh -o ConnectTimeout=5 ubuntu@$node 'echo "✅ Connected to $(hostname)"' || echo "❌ Failed to connect to $node"
done

# Validate Ansible can actually reach the cluster through inventory.yml
echo "Validating Ansible connectivity to the cluster..."
ansible all -i inventory.yml -m ping

echo "SSH setup complete!"
echo "Python $(python3 --version) and aliases are ready. Open a new shell or run: source ~/.bash_aliases"
