output "file_system_id" {
  description = "EFS filesystem ID. Use this in PVC/StorageClass definitions."
  value       = module.efs.file_system_id
}

output "file_system_dns_name" {
  description = "EFS filesystem DNS name."
  value       = module.efs.file_system_dns_name
}

output "security_group_id" {
  description = "Security group ID for the EFS mount targets."
  value       = module.efs.security_group_id
}

output "storage_class_name" {
  description = "Kubernetes StorageClass name for EFS dynamic provisioning."
  value       = module.efs.storage_class_name
}
