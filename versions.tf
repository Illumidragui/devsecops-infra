terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    porkbun = {
      source  = "marcfrederick/porkbun"
      version = "~> 1.3"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

provider "porkbun" {
  api_key        = var.porkbun_api_key
  secret_api_key = var.porkbun_secret_api_key
}
