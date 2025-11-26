############################################
# Provider and Region
############################################

provider "aws" {
  region = var.aws_region
}


############################################
# VPC Data Sources
# Get default VPC and its subnets
############################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


############################################
# Get Latest Ubuntu 22.04 LTS AMI
############################################

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


############################################
# Security Group
############################################

resource "aws_security_group" "snipeit_sg" {
  name        = "snipeit-ec2-sg"
  description = "Allow HTTP/HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "snipeit-sg"
  }
}


############################################
# EC2 IAM Role Profile
############################################

resource "aws_iam_instance_profile" "snipeit_instance_profile" {
  name = "SnipeitInstanceProfile"
  role = "SnipeitEc2Role" # Make sure this role exists!
}


############################################
# EC2 Instance
############################################

resource "aws_instance" "snipeit_ec2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  #subnet_id uses aws_subnets instead of deprecated aws_subnet_ids
  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [aws_security_group.snipeit_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.snipeit_instance_profile.name

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name        = "snipeit-host"
    SSMTarget   = "snipeit"
    Environment = "prod"
  }
}


############################################
# Elastic IP
############################################

resource "aws_eip" "snipeit_eip" {
  domain = "vpc"

  tags = {
    Name = "snipeit-static-ip"
  }
}

resource "aws_eip_association" "snipeit_eip_assoc" {
  instance_id   = aws_instance.snipeit_ec2.id
  allocation_id = aws_eip.snipeit_eip.id
}
