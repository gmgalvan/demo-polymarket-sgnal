output "role_name" {
  description = "The name of the IAM role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "The ARN of the IAM role."
  value       = aws_iam_role.this.arn
}

output "inline_policies" {
  description = "The inline policies attached to the role."
  value = [for policy in aws_iam_role_policy.inline_policies : {
    name   = policy.name
    policy = policy.policy
  }]
}
