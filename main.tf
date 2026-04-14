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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

locals {
  aws_region     = var.aws_region
  project_name   = var.project_name
  environment    = var.environment
  instance_type  = var.instance_type
}

# Creation of VPC, subnets, NAT Gateway, and route tables
module "vpc" {
  create       = true
  source       = "./tf-modules/aws-vpc"
  project_name = local.project_name
  environment  = local.environment
  aws_region   = local.aws_region
}

# Creation of EC2 k3s node. Depends on VPC.
# Set create = false and apply to first provision the VPC.
# After that, set create = true to deploy the EC2 instance.
module "ec2" {
  create             = true
  source             = "./tf-modules/aws-ec2"
  project_name       = local.project_name
  environment        = local.environment
  instance_type      = local.instance_type
  ssh_public_key     = var.ssh_public_key
  subnet_id          = module.vpc.private_subnet_id
  vpc_id             = module.vpc.vpc_id
  tailscale_authkey  = var.tailscale_authkey

  depends_on = [module.vpc]
}

# Deployment of ArgoCD + App of Apps Helm chart.
# Set create = false and apply to first provision the VPC + EC2.
# After EC2 is up, copy kubeconfig (see README), then set create = true.
module "helm-argocd" {
  create                   = true
  source                   = "./tf-modules/helm-argocd"
  kubeconfig_path          = var.kubeconfig_path
  argocd_github_repo       = var.argocd_github_repo
  tailscale_oauth_clientid = var.tailscale_oauth_clientid
  tailscale_oauth_secret   = var.tailscale_oauth_secret

}
