#!/bin/bash
set -e

##############################################
# UPDATE BASE SYSTEM
##############################################
# I install core packages, AWS CLI, and git.
apt-get update -y
apt-get install -y ca-certificates curl gnupg awscli snapd git

##############################################
# INSTALL SSM AGENT (FOR SESSION MANAGER)
##############################################
# I install and enable the SSM agent so I can connect without SSH.
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

##############################################
# INSTALL DOCKER
##############################################
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

##############################################
# CREATE DIRECTORIES FOR ENV FILES
##############################################
# I create the directories where my .env files will live.
mkdir -p /opt/snipeit
mkdir -p /opt/flask
chown -R ubuntu:ubuntu /opt/snipeit /opt/flask

##############################################
# LOGIN TO ECR
##############################################
# I log in to my ECR registry so Docker can pull images during bootstrap.
aws ecr get-login-password --region eu-west-2 | docker login \
  --username AWS \
  --password-stdin 448049798930.dkr.ecr.eu-west-2.amazonaws.com

##############################################
# PULL V2 IMAGES (LATEST TAG)
##############################################
docker pull 448049798930.dkr.ecr.eu-west-2.amazonaws.com/snipeit-v2:latest
docker pull 448049798930.dkr.ecr.eu-west-2.amazonaws.com/flask-middleware-v2:latest

##############################################
# RUN SNIPE-IT V2 CONTAINER
##############################################
docker run -d \
  --name snipeit-v2 \
  -p 80:80 \
  --env-file /opt/snipeit/.env.snipeit \
  448049798930.dkr.ecr.eu-west-2.amazonaws.com/snipeit-v2:latest

##############################################
# RUN FLASK V2 CONTAINER
##############################################
docker run -d \
  --name flask-v2 \
  -p 5000:5000 \
  --env-file /opt/flask/.env.flask \
  448049798930.dkr.ecr.eu-west-2.amazonaws.com/flask-middleware-v2:latest
