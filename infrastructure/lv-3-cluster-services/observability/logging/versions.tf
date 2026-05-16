terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "352-demo-dev-s3b-tfstate-backend"
    key          = "dev/lv-3-cluster-services/observability/logging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}
