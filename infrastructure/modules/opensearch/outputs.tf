output "domain_endpoint" {
  description = "OpenSearch domain HTTPS endpoint (use as OPENSEARCH_ENDPOINT env var)."
  value       = "https://${aws_opensearch_domain.this.endpoint}"
}

output "domain_arn" {
  description = "OpenSearch domain ARN."
  value       = aws_opensearch_domain.this.arn
}

output "domain_id" {
  description = "OpenSearch domain unique identifier."
  value       = aws_opensearch_domain.this.domain_id
}

output "security_group_id" {
  description = "Security group ID attached to the OpenSearch domain."
  value       = aws_security_group.opensearch.id
}

output "agent_role_arn" {
  description = "IAM role ARN for agent pods (annotate the K8s service account with this)."
  value       = aws_iam_role.agent.arn
}

output "agent_role_name" {
  description = "IAM role name for agent pods."
  value       = aws_iam_role.agent.name
}
