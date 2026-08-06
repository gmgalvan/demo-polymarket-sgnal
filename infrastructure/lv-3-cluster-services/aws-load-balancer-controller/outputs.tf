output "cluster_name" {
  description = "EKS cluster where the controller is installed."
  value       = local.cluster_name
}

output "namespace" {
  description = "Kubernetes namespace containing the controller."
  value       = var.namespace
}

output "service_account_name" {
  description = "IRSA-enabled Kubernetes service account."
  value       = var.service_account_name
}

output "iam_role_arn" {
  description = "IAM role assumed by AWS Load Balancer Controller."
  value       = module.irsa.arn
}

output "helm_release_name" {
  description = "Helm release name."
  value       = helm_release.aws_load_balancer_controller.name
}
