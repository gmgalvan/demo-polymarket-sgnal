data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket  = var.vpc_state_bucket
    key     = var.vpc_state_key
    region  = var.vpc_state_region
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

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name               = var.cluster_name
  cluster_version            = var.cluster_version
  eks_endpoint_public_access = var.eks_endpoint_public_access
  vpc_id                     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids                 = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  core_node_instance_type = var.core_node_instance_type
  core_node_min_size      = var.core_node_min_size
  core_node_desired_size  = var.core_node_desired_size
  core_node_max_size      = var.core_node_max_size

  l40s_instance_type     = var.l40s_instance_type
  l40s_node_min_size     = var.l40s_node_min_size
  l40s_node_desired_size = var.l40s_node_desired_size
  l40s_node_max_size     = var.l40s_node_max_size
  l40s_node_disk_size    = var.l40s_node_disk_size

  inferentia_instance_type     = var.inferentia_instance_type
  inferentia_node_min_size     = var.inferentia_node_min_size
  inferentia_node_desired_size = var.inferentia_node_desired_size
  inferentia_node_max_size     = var.inferentia_node_max_size
  inferentia_node_disk_size    = var.inferentia_node_disk_size

  karpenter_namespace = var.karpenter_namespace
  common_tags         = local.common_tags
}

module "eks_karpenter" {
  source = "../../modules/eks-karpenter"

  cluster_name                      = module.eks_cluster.cluster_name
  cluster_endpoint                  = module.eks_cluster.cluster_endpoint
  karpenter_iam_role_arn            = module.eks_cluster.karpenter_iam_role_arn
  karpenter_interruption_queue_name = module.eks_cluster.karpenter_interruption_queue_name
  karpenter_namespace               = var.karpenter_namespace
  karpenter_chart_version           = var.karpenter_chart_version

  depends_on = [module.eks_cluster]
}
