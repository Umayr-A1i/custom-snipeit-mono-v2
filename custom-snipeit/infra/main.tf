########################################
# AWS PROVIDER
########################################

# I tell Terraform which AWS region to use.
provider "aws" {
  region = var.aws_region
}

########################################
# DATA SOURCES
########################################

# I fetch the default VPC in my AWS account.
data "aws_vpc" "default" {
  default = true
}

# I fetch all subnets in that VPC (public + private).
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# I fetch the latest Ubuntu 22.04 AMI for my EC2 instance.
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

  owners = ["099720109477"]  # Canonical (Ubuntu)
}

#######################################################
# MYSQL DB PASSWORD FROM SECRETS MANAGER (V2)
#######################################################

# I read the DB password I created in Secrets Manager under /custom-snipeit-v2/db_password.
data "aws_secretsmanager_secret_version" "db_password_v2" {
  secret_id = "/custom-snipeit-v2/db_password"
}

########################################
# SECURITY GROUPS FOR V2
########################################

# MAIN EC2 SG (HTTP/HTTPS/SSH)
resource "aws_security_group" "snipeit_sg" {
  name        = "snipeit-ec2-sg-v2"
  description = "Allow HTTP/HTTPS + SSH"
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

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "snipeit-sg-v2"
  }
}

# RDS SECURITY GROUP (ONLY EC2 CAN CONNECT)
resource "aws_security_group" "snipeit_db_sg" {
  name        = "snipeit-db-sg-v2"
  description = "MySQL ingress only from EC2 SG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "Allow MySQL from EC2 instance only"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.snipeit_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "snipeit-db-sg-v2"
  }
}

########################################
# SSH KEY PAIR FOR V2
########################################

resource "aws_key_pair" "snipeit_key" {
  key_name   = "umayr-dev-key-v2"
  public_key = file("${path.module}/umayr-dev-key-v2.pub")

  lifecycle {
    ignore_changes = [public_key]
  }
}

########################################
# IAM ROLE + INSTANCE PROFILE FOR EC2
########################################

resource "aws_iam_role" "snipeit_ec2_role" {
  name = "SnipeitEc2Role-v2"

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
}

# I attach the SSM managed policy so I can connect via Session Manager.
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# I attach read-only ECR policy so EC2 can pull my container images.
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# I create a custom policy so EC2 can read my V2 secrets from Secrets Manager.
resource "aws_iam_role_policy" "secrets_policy" {
  name = "SnipeitSecretsAccess-v2"
  role = aws_iam_role.snipeit_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:eu-west-2:448049798930:secret:/custom-snipeit-v2/*"
    }]
  })
}

resource "aws_iam_instance_profile" "snipeit_instance_profile" {
  name = "SnipeitInstanceProfile-v2"
  role = aws_iam_role.snipeit_ec2_role.name
}

########################################
# ECR REPOSITORIES FOR V2
########################################

resource "aws_ecr_repository" "snipeit" {
  name         = "snipeit-v2"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "flask_middleware" {
  name         = "flask-middleware-v2"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

########################################
# RDS SUBNET GROUP (DEFAULT VPC SUBNETS)
########################################

resource "aws_db_subnet_group" "snipeit_v2" {
  name       = "snipeit-v2-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "snipeit-v2-db-subnet-group"
  }
}

########################################
# RDS MYSQL INSTANCE FOR V2
########################################

resource "aws_db_instance" "snipeit_v2" {
  identifier        = "snipeit-v2-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.rds_instance_size
  allocated_storage = 20

  db_name  = "snipeit_v2"  # This will be DB_DATABASE in .env.snipeit.
  username = "snipeit_v2"  # This will be DB_USERNAME in .env.snipeit.

  # I decode the JSON from Secrets Manager and extract the "value" field.
  password = jsondecode(data.aws_secretsmanager_secret_version.db_password_v2.secret_string)["value"]

  db_subnet_group_name   = aws_db_subnet_group.snipeit_v2.name
  vpc_security_group_ids = [aws_security_group.snipeit_db_sg.id]

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "snipeit-v2-db"
  }
}

########################################
# ELASTIC IP (MANAGED BY TERRAFORM)
########################################

resource "aws_eip" "snipeit_eip" {
  domain = "vpc"

  tags = {
    Name = "snipeit-static-ip-v2"
  }
}

########################################
# EC2 INSTANCE
########################################

resource "aws_instance" "snipeit_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.snipeit_sg.id]

  iam_instance_profile = aws_iam_instance_profile.snipeit_instance_profile.name

  key_name = aws_key_pair.snipeit_key.key_name

  # I use user_data.sh to bootstrap Docker, SSM, and containers.
  user_data = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name        = "snipeit-host-v2"
    Environment = "prod-v2"
    SSMTarget   = "snipeit-v2"
  }
}

########################################
# ASSOCIATE STATIC IP TO EC2
########################################

resource "aws_eip_association" "snipeit_association" {
  instance_id   = aws_instance.snipeit_ec2.id
  allocation_id = aws_eip.snipeit_eip.id
}
