variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "install_efs_csi_driver" {
  description = "Install the EFS CSI driver via Helm."
  type        = bool
  default     = true
}

variable "create_storage_class" {
  description = "Create a Kubernetes StorageClass for dynamic EFS provisioning."
  type        = bool
  default     = true
}
