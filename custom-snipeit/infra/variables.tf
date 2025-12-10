variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "root_volume_size" {
  type    = number
  default = 20 #Allocating 20gb to the root disk of the EC2
}

variable "rds_instance_size" {
  type    = string 
  default = "db.t3.micro" #Keeping the RDS small as this is a POC
}