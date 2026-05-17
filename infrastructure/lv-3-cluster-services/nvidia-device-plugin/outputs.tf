output "cluster_name" {
  description = "EKS cluster name consumed from lv-2 remote state."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "plugin_namespace" {
  description = "Namespace where the NVIDIA device plugin is installed."
  value       = var.plugin_namespace
}
