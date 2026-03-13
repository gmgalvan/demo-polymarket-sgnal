output "cluster_name" {
  description = "EKS cluster name consumed from lv-2 remote state."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "karpenter_namespace" {
  description = "Namespace where Karpenter is installed."
  value       = var.karpenter_namespace
}
