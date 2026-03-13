output "repository_url" {
  description = "The URL of the repository."
  value       = aws_ecr_repository.repository.repository_url
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.repository.name
}

output "repository_arn" {
  description = "The ARN of the repository."
  value       = aws_ecr_repository.repository.arn
}
