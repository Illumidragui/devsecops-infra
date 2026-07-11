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

locals {
  aws_region    = var.aws_region
  project_name  = var.project_name
  environment   = var.environment
  instance_type = var.instance_type
}

# Creation of VPC, subnets, NAT Gateway, and route tables
module "vpc" {
  source       = "./tf-modules/aws-vpc"
  project_name = local.project_name
  environment  = local.environment
  aws_region   = local.aws_region
}

# Creation of EC2 k3s node. Depends on VPC.
module "ec2" {
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

