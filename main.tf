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
  subnet_id          = module.vpc.public_subnet_id
  vpc_id             = module.vpc.vpc_id
  tailscale_authkey  = var.tailscale_authkey
  tailscale_hostname = var.tailscale_hostname

  depends_on = [module.vpc]
}

# EIP lives outside module.ec2 so it survives terraform destroy -target=module.ec2.
# The association is re-created on each deploy and torn down with the instance.
resource "aws_eip" "k3s" {
  domain = "vpc"

  tags = {
    Name = "${local.project_name}-${local.environment}-eip"
  }
}

resource "aws_eip_association" "k3s" {
  count         = 1
  instance_id   = module.ec2.instance_id
  allocation_id = aws_eip.k3s.allocation_id

  depends_on = [module.ec2]
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
