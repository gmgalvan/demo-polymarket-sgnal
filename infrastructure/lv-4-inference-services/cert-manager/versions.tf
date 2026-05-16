terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "352-demo-dev-s3b-tfstate-backend"
    key          = "dev/lv-4-inference-services/cert-manager/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13"
    }
  }
}
