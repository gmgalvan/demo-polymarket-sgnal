output "file_system_id" {
  description = "EFS filesystem ID."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "EFS filesystem ARN."
  value       = aws_efs_file_system.this.arn
}

output "file_system_dns_name" {
  description = "EFS filesystem DNS name."
  value       = aws_efs_file_system.this.dns_name
}

output "security_group_id" {
  description = "Security group ID for the EFS mount targets."
  value       = aws_security_group.efs.id
}

output "mount_target_ids" {
  description = "Map of subnet ID to mount target ID."
  value       = { for k, v in aws_efs_mount_target.this : k => v.id }
}

output "storage_class_name" {
  description = "Kubernetes StorageClass name (if created)."
  value       = var.create_storage_class ? var.storage_class_name : null
}
