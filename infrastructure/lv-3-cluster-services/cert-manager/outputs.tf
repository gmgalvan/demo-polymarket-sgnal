output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed."
  value       = var.cert_manager_namespace
}
