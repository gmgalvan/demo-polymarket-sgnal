output "cluster_name" {
  description = "EKS cluster where ExternalDNS is installed."
  value       = local.cluster_name
}

output "namespace" {
  description = "Kubernetes namespace containing ExternalDNS."
  value       = var.namespace
}

output "service_account_name" {
  description = "IRSA-enabled Kubernetes service account."
  value       = var.service_account_name
}

output "iam_role_arn" {
  description = "IAM role assumed by ExternalDNS."
  value       = module.irsa.arn
}

output "managed_hosted_zone_id" {
  description = "Only Route 53 hosted zone ExternalDNS may modify."
  value       = var.hosted_zone_id
}

output "domain_filter" {
  description = "DNS suffix watched by ExternalDNS."
  value       = var.domain_filter
}
