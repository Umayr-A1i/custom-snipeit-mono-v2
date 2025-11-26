#!/bin/bash
set -e

# I update the base OS packages first.
apt-get update -y
apt-get install -y ca-certificates curl gnupg awscli snapd git

##############################################
# Install SSM Agent (so I can use SSM/CI/CD)
##############################################
# I install the SSM agent via snap because it's the recommended path on Ubuntu.
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

##############################################
# Install Docker (engine + CLI + plugins)
##############################################
# I set up Docker’s official APT repository.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# I enable Docker on boot and start it now.
systemctl enable docker
systemctl start docker

# I let the ubuntu user run docker without sudo.
usermod -aG docker ubuntu

##############################################
# (Optional) Docker Compose v2 standalone
##############################################
# I also install the docker-compose v2 binary so I can run `docker-compose`
# as well as `docker compose` if I want to.
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

##############################################
# Prepare app directory and clone repo
##############################################
# I create a base directory for the Snipe-IT stack.
mkdir -p /opt/snipeit
chown -R ubuntu:ubuntu /opt/snipeit

# I clone my monorepo so the CI/CD job has something to work with.
if [ ! -d "/opt/snipeit/custom-snipeit-mono" ]; then
  git clone https://github.com/Umayr-A1i/custom-snipeit-mono.git /opt/snipeit/custom-snipeit-mono
  chown -R ubuntu:ubuntu /opt/snipeit/custom-snipeit-mono
fi

