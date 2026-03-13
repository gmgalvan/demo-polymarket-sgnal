terraform {
  backend "s3" {
    bucket       = "352-demo-dev-s3b-tfstate-backend"
    key          = "dev/lv-2-core-compute/eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}
