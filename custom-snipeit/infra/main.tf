########################################
# DATA SOURCES
########################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

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

  owners = ["099720109477"]
}

########################################
# SECURITY GROUP
########################################

resource "aws_security_group" "snipeit_sg" {
  name        = "snipeit-ec2-sg-v2"   ### CHANGED FOR V2
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
    Name = "snipeit-sg-v2"   ### CHANGED FOR V2
  }
}

########################################
# SSH KEY PAIR (NEW FOR V2)
########################################

resource "aws_key_pair" "snipeit_key" {
  key_name   = "umayr-dev-key-v2"   ### CHANGED FOR V2 (new key)
  public_key = file("${path.module}/umayr-dev-key-v2.pub")   ### CHANGED FOR V2
}

########################################
# IAM ROLE + INSTANCE PROFILE
########################################

resource "aws_iam_role" "snipeit_ec2_role" {
  name = "SnipeitEc2Role-v2"   ### CHANGED FOR V2

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

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.snipeit_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "snipeit_instance_profile" {
  name = "SnipeitInstanceProfile-v2"   ### CHANGED FOR V2
  role = aws_iam_role.snipeit_ec2_role.name
}

########################################
# ECR (new repos for v2)
########################################

resource "aws_ecr_repository" "snipeit" {
  name         = "snipeit-v2"   ### CHANGED FOR V2
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "snipeit-v2"   ### CHANGED FOR V2
  }
}

resource "aws_ecr_repository" "flask_middleware" {
  name         = "flask-middleware-v2"   ### CHANGED FOR V2
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "flask-middleware-v2"  ### CHANGED FOR V2
  }
}

########################################
# ELASTIC IP
########################################

resource "aws_eip" "snipeit_eip" {
  domain = "vpc"

  tags = {
    Name = "snipeit-static-ip-v2"   ### CHANGED FOR V2
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

  key_name = aws_key_pair.snipeit_key.key_name   ### CHANGED FOR V2

  user_data = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "snipeit-host-v2"   ### CHANGED FOR V2
    Environment = "prod-v2"           ### CHANGED FOR V2
    SSMTarget   = "snipeit-v2"        ### CHANGED FOR V2
  }
}

########################################
# ASSOCIATE STATIC IP
########################################

resource "aws_eip_association" "snipeit_association" {
  allocation_id = aws_eip.snipeit_eip.id
  instance_id   = aws_instance.snipeit_ec2.id
}
