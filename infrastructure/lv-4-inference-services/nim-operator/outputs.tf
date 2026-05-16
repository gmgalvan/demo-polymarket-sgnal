output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "nim_operator_namespace" {
  description = "Namespace where the NVIDIA NIM Operator is installed."
  value       = var.nim_operator_namespace
}
