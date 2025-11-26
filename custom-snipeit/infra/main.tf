########################################
# PROVIDERS
########################################
provider "aws" {
  region = var.aws_region
}

########################################
# DATA SOURCES – existing AWS resources
########################################

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu AMI (22.04 LTS)
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

########################################
# ECR REPOSITORIES
########################################
# These MUST exist before CI/CD can push images
# Since you created them manually, run:
#
# terraform import aws_ecr_repository.snipeit snipeit
# terraform import aws_ecr_repository.flask_middleware flask-middleware
########################################

resource "aws_ecr_repository" "snipeit" {
  name                 = "snipeit"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "flask_middleware" {
  name                 = "flask-middleware"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

########################################
# IAM ROLE FOR EC2 (SSM + ECR access)
########################################

resource "aws_iam_role" "snipeit_ec2_role" {
  name = "SnipeitEc2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "snipeit_ec2_policy" {
  name = "SnipeitEc2Policy"
  role = aws_iam_role.snipeit_ec2_role.id

  # EC2 role must access ECR, SSM, CloudWatch
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:*",
          "ssm:*",
          "logs:*",
          "cloudwatch:*"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = "iam:PassRole",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "snipeit_instance_profile" {
  name = "SnipeitInstanceProfile"
  role = aws_iam_role.snipeit_ec2_role.name
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
# ELASTIC IP (STATIC)
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
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.snipeit_instance_profile.name
  vpc_security_group_ids = [aws_security_group.snipeit_sg.id]

  tags = {
    Name        = "snipeit-host"
    Environment = "prod"
    SSMTarget   = "snipeit"
  }

  # user_data.sh will install SSM agent, Docker, Docker Compose, etc.
  user_data = file("${path.module}/user_data.sh")
}

########################################
# ASSOCIATE STATIC IP WITH INSTANCE
########################################

resource "aws_eip_association" "snipeit_eip_assoc" {
  allocation_id = aws_eip.snipeit_eip.id
  instance_id   = aws_instance.snipeit_ec2.id
}

########################################
# OUTPUTS FOR CI/CD
########################################

output "ec2_instance_id" {
  value = aws_instance.snipeit_ec2.id
}

output "static_ip" {
  value = aws_eip.snipeit_eip.public_ip
}

output "ecr_snipeit" {
  value = aws_ecr_repository.snipeit.repository_url
}

output "ecr_flask" {
  value = aws_ecr_repository.flask_middleware.repository_url
}
