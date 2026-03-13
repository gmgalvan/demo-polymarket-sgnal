output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = module.eks_cluster.cluster_version
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN used for IRSA."
  value       = module.eks_cluster.cluster_oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID consumed from lv-0 remote state."
  value       = data.terraform_remote_state.vpc.outputs.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs consumed from lv-0 remote state."
  value       = data.terraform_remote_state.vpc.outputs.private_subnet_ids
}

output "karpenter_iam_role_arn" {
  description = "IAM role ARN used by Karpenter service account."
  value       = module.eks_cluster.karpenter_iam_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name used by Karpenter-launched nodes."
  value       = module.eks_cluster.karpenter_instance_profile_name
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name used by Karpenter interruption handling."
  value       = module.eks_cluster.karpenter_interruption_queue_name
}

output "cluster_primary_security_group_id" {
  description = "Cluster primary security group ID."
  value       = module.eks_cluster.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "Node security group ID."
  value       = module.eks_cluster.node_security_group_id
}

output "l40s_instance_type" {
  description = "Configured L40S instance type for GPU node group."
  value       = var.l40s_instance_type
}

output "inferentia_instance_type" {
  description = "Configured Inferentia instance type for Neuron node group."
  value       = var.inferentia_instance_type
}
