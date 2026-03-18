# ── Remote state: VPC (lv-0) ──────────────────────────────────────────────────
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket  = var.vpc_state_bucket
    key     = var.vpc_state_key
    region  = var.vpc_state_region
    encrypt = true
  }
}

# ── Remote state: EKS (lv-2/eks) ──────────────────────────────────────────────
data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
    },
    var.additional_tags
  )
}

module "opensearch" {
  source = "../../modules/opensearch"

  domain_name        = var.domain_name
  engine_version     = var.engine_version
  instance_type      = var.instance_type
  instance_count     = var.instance_count
  ebs_volume_size_gb = var.ebs_volume_size_gb

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # Allow traffic from EKS node security group
  allowed_security_group_ids = [
    data.terraform_remote_state.eks.outputs.node_security_group_id,
  ]

  aws_region        = var.aws_region
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.cluster_oidc_provider_arn
  master_user_arn   = var.master_user_arn

  agent_namespace       = var.agent_namespace
  agent_service_account = var.agent_service_account

  common_tags = local.common_tags
}
