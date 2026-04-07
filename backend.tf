terraform {
  backend "s3" {
    bucket  = "devsecops-infra-tfstate"
    key     = "k8s-cluster/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}