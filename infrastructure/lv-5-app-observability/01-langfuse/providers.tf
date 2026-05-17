terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "352-demo-dev-s3b-tfstate-backend"
    key          = "dev/lv-5-app-observability/01-langfuse/terraform.tfstate"
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

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

data "terraform_remote_state" "security_and_config" {
  backend = "s3"

  config = {
    bucket  = var.security_and_config_state_bucket
    key     = var.security_and_config_state_key
    region  = var.security_and_config_state_region
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_secretsmanager_secret_version" "langfuse_postgres_password" {
  secret_id = data.terraform_remote_state.security_and_config.outputs.managed_secret_names["langfuse"]
}

data "aws_secretsmanager_secret_version" "langfuse_nextauth_secret" {
  secret_id = data.terraform_remote_state.security_and_config.outputs.managed_secret_names["langfuse"]
}

data "aws_secretsmanager_secret_version" "langfuse_salt" {
  secret_id = data.terraform_remote_state.security_and_config.outputs.managed_secret_names["langfuse"]
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.aws_eks_cluster.this.name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
