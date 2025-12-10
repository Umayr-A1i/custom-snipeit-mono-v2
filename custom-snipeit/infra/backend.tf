terraform {
  backend "s3" {
    bucket         = "terahost-snipeit-tfstate-umayr"
    key            = "v2/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terahost-snipeit-tf-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
