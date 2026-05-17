output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "langfuse_namespace" {
  description = "Namespace where LangFuse is deployed."
  value       = var.langfuse_namespace
}

output "langfuse_endpoint" {
  description = "In-cluster LangFuse endpoint."
  value       = "http://langfuse.${var.langfuse_namespace}.svc.cluster.local:3000"
}
