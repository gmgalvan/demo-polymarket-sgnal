output "managed_secret_names" {
  description = "Secret names created and owned by this stack."
  value       = module.managed_secrets.secret_names
}

output "managed_secret_arns" {
  description = "Secret ARNs created and owned by this stack."
  value       = module.managed_secrets.secret_arns
}

output "external_secret_names" {
  description = "Optional externally-sourced secret names created by this stack."
  value       = module.external_secrets.secret_names
}

output "config_parameter_names" {
  description = "SSM parameter names created by this stack."
  value       = { for key, param in aws_ssm_parameter.config : key => param.name }
}
