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
