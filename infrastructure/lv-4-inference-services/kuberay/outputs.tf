output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "kuberay_namespace" {
  description = "Namespace where KubeRay operator is installed."
  value       = var.kuberay_namespace
}
