########################################
# DATA SOURCES
########################################

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# All subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Reliable, region-compatible Ubuntu 22.04 AMI lookup
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

########################################
# SECURITY GROUP
########################################

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

########################################
# IAM ROLE FOR EC2 (SSM + ECR PULL)
########################################

resource "aws_iam_role" "snipeit_ec2_role" {
  name = "SnipeitEc2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  lifecycle {
    ignore_changes = [
      description,
      tags,
      assume_role_policy
    ]
  }
}

# Attach AWS managed policies for SSM and ECR pull
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "snipeit_instance_profile" {
  name = "SnipeitInstanceProfile"
  role = aws_iam_role.snipeit_ec2_role.name

  lifecycle {
    ignore_changes = [role]
  }
}

########################################
# ECR REPOSITORIES
########################################

resource "aws_ecr_repository" "snipeit" {
  name = "snipeit"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "snipeit"
  }
}

resource "aws_ecr_repository" "flask_middleware" {
  name = "flask-middleware"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "flask-middleware"
  }
}

########################################
# STATIC IP (EIP)
########################################

resource "aws_eip" "snipeit_eip" {
  domain = "vpc"

  tags = {
    Name = "snipeit-static-ip"
  }
}

########################################
# EC2 INSTANCE
########################################

resource "aws_instance" "snipeit_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.snipeit_sg.id]

  iam_instance_profile = aws_iam_instance_profile.snipeit_instance_profile.name

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name        = "snipeit-host"
    Environment = "prod"
    SSMTarget   = "snipeit"
  }
}

########################################
# EIP ASSOCIATION
########################################

resource "aws_eip_association" "snipeit_association" {
  allocation_id = aws_eip.snipeit_eip.id
  instance_id   = aws_instance.snipeit_ec2.id
}
