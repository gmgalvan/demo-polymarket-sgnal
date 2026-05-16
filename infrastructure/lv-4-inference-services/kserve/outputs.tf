output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "kserve_namespace" {
  description = "Namespace where KServe is installed."
  value       = var.kserve_namespace
}
