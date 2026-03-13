output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data required to connect to the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN used for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "karpenter_iam_role_arn" {
  description = "IAM role ARN used by Karpenter service account."
  value       = module.karpenter.iam_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name used by Karpenter-launched nodes."
  value       = module.karpenter.instance_profile_name
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name used by Karpenter interruption handling."
  value       = module.karpenter.queue_name
}

output "cluster_primary_security_group_id" {
  description = "Cluster primary security group ID."
  value       = module.eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "Node security group ID."
  value       = module.eks.node_security_group_id
}
