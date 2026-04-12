terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/devsecops-config"
  }
}

module "vpc" {
  source       = "./tf-modules/aws-vpc"
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}

module "ec2" {
  source         = "./tf-modules/aws-ec2"
  project_name   = var.project_name
  environment    = var.environment
  instance_type  = var.instance_type
  ssh_public_key = var.ssh_public_key
  my_ip          = var.my_ip
  subnet_id      = module.vpc.public_subnet_id
  vpc_id         = module.vpc.vpc_id

  depends_on = [module.vpc]
}

module "helm-argocd" {
  source      = "./tf-modules/helm-argocd"
  instance_ip = module.ec2.instance_ip

  depends_on = [module.ec2]

  providers = {
    helm = helm
  }
}