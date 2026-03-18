output "cluster_name" {
  description = "EKS cluster name (from lv-2 remote state)."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "kserve_namespace" {
  description = "Namespace where KServe is installed."
  value       = var.install_kserve ? var.kserve_namespace : null
}

output "kuberay_namespace" {
  description = "Namespace where KubeRay operator is installed."
  value       = var.install_kuberay ? var.kuberay_namespace : null
}

output "nim_operator_namespace" {
  description = "Namespace where the NVIDIA NIM Operator is installed."
  value       = var.install_nim_operator ? var.nim_operator_namespace : null
}
