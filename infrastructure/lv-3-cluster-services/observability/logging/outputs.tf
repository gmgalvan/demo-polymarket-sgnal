output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "logging_namespace" {
  description = "Namespace where Loki and Fluent Bit are deployed."
  value       = var.logging_namespace
}

output "loki_endpoint" {
  description = "In-cluster Loki push/query gateway endpoint."
  value       = "http://loki-gateway.${var.logging_namespace}.svc.cluster.local:80"
}
