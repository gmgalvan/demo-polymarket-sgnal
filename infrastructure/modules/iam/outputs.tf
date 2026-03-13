output "iam_lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role."
  value       = aws_iam_role.lambda.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Lambda."
  value       = aws_iam_role.lambda.name
}
