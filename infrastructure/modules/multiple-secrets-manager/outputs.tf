output "secret_names" {
  description = "Secret names keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.name }
}

output "secret_arns" {
  description = "Secret ARNs keyed by logical secret key."
  value       = { for key, secret in aws_secretsmanager_secret.this : key => secret.arn }
}
