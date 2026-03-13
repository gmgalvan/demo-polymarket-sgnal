output "parameter_names" {
  description = "List of names for the created SSM parameters"
  value       = [for param in aws_ssm_parameter.parameters : param.name]
}
