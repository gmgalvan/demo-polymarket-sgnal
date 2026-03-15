variable "name" {
  description = "Name prefix for EFS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EFS will be created."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets (one per AZ)."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID of EKS worker nodes (allowed NFS ingress)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA (EFS CSI driver service account)."
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "KMS key ARN for EFS encryption at rest. Uses AWS-managed key if null."
  type        = string
  default     = null
}

variable "performance_mode" {
  description = "EFS performance mode: generalPurpose or maxIO."
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "EFS throughput mode: bursting or elastic."
  type        = string
  default     = "elastic"
}

variable "install_efs_csi_driver" {
  description = "Install the EFS CSI driver via Helm."
  type        = bool
  default     = true
}

variable "efs_csi_driver_version" {
  description = "Helm chart version for aws-efs-csi-driver. Null = latest."
  type        = string
  default     = null
}

variable "create_storage_class" {
  description = "Create a Kubernetes StorageClass for dynamic EFS provisioning."
  type        = bool
  default     = true
}

variable "storage_class_name" {
  description = "Name of the Kubernetes StorageClass to create."
  type        = string
  default     = "efs-sc"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
