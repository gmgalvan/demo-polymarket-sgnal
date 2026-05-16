output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "monitoring_namespace" {
  description = "Namespace where Neuron observability resources are installed."
  value       = var.monitoring_namespace
}
