output "opensearch_endpoint" {
  description = "OpenSearch HTTPS endpoint — set as OPENSEARCH_ENDPOINT in agent pods."
  value       = module.opensearch.domain_endpoint
}

output "opensearch_domain_arn" {
  description = "OpenSearch domain ARN."
  value       = module.opensearch.domain_arn
}

output "agent_role_arn" {
  description = "IRSA role ARN — annotate the K8s service account with this value."
  value       = module.opensearch.agent_role_arn
}

output "security_group_id" {
  description = "OpenSearch security group ID."
  value       = module.opensearch.security_group_id
}
