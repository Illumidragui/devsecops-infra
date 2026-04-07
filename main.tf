# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

module "aws" {
  source = "./tf-modules/aws"

  project_name   = var.project_name
  environment    = var.environment
  instance_type  = var.instance_type
  ssh_public_key = var.ssh_public_key
  my_ip          = var.my_ip
  aws_region     = var.aws_region
}

module "k8s_platform" {
  source = "./tf-modules/k8s-platform"

  depends_on  = [module.aws]
  instance_ip = module.aws.instance_ip
}