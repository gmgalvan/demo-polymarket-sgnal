data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

module "eks_karpenter" {
  source = "../../modules/eks-karpenter"

  cluster_name                      = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_endpoint                  = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_version                   = data.terraform_remote_state.eks.outputs.cluster_version
  karpenter_instance_profile_name   = data.terraform_remote_state.eks.outputs.karpenter_instance_profile_name
  private_subnet_ids                = data.terraform_remote_state.eks.outputs.private_subnet_ids
  cluster_primary_security_group_id = data.terraform_remote_state.eks.outputs.cluster_primary_security_group_id
  node_security_group_id            = data.terraform_remote_state.eks.outputs.node_security_group_id
  karpenter_iam_role_arn            = data.terraform_remote_state.eks.outputs.karpenter_iam_role_arn
  karpenter_interruption_queue_name = data.terraform_remote_state.eks.outputs.karpenter_interruption_queue_name
  karpenter_namespace               = var.karpenter_namespace
  karpenter_chart_version           = var.karpenter_chart_version
  core_node_instance_type           = data.terraform_remote_state.eks.outputs.core_node_instance_type
  l40s_instance_type                = data.terraform_remote_state.eks.outputs.l40s_instance_type
  inferentia_instance_type          = data.terraform_remote_state.eks.outputs.inferentia_instance_type
  install_nvidia_device_plugin      = var.install_nvidia_device_plugin
  install_neuron_device_plugin      = var.install_neuron_device_plugin
  enable_karpenter_nodepools        = var.enable_karpenter_nodepools
}
