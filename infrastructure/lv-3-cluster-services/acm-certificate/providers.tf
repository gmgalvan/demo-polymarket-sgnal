terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  backend "s3" {
    bucket       = "352-demo-dev-s3b-tfstate-backend"
    key          = "dev/lv-3-cluster-services/acm-certificate/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  # Must be us-east-1 for a cert used by CloudFront; for an ALB (our case)
  # the cert just needs to be in the SAME region as the ALB, which is also
  # us-east-1 here - so no cross-region provider alias needed.
  region = var.aws_region
}
