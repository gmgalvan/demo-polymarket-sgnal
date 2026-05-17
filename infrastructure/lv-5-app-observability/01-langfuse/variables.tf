variable "aws_region" {
  description = "AWS region where EKS cluster is deployed."
  type        = string
  default     = "us-east-1"
}

variable "eks_state_bucket" {
  description = "S3 bucket containing lv-2 EKS Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "eks_state_key" {
  description = "S3 key for lv-2 EKS Terraform state."
  type        = string
  default     = "dev/lv-2-core-compute/eks/terraform.tfstate"
}

variable "eks_state_region" {
  description = "Region where lv-2 EKS state backend lives."
  type        = string
  default     = "us-east-1"
}

variable "security_and_config_state_bucket" {
  description = "S3 bucket containing lv-1 security/config Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "security_and_config_state_key" {
  description = "S3 key for lv-1 security/config Terraform state."
  type        = string
  default     = "dev/lv-1-security-and-config/secrets/terraform.tfstate"
}

variable "security_and_config_state_region" {
  description = "Region where lv-1 security/config state backend lives."
  type        = string
  default     = "us-east-1"
}

variable "langfuse_namespace" {
  description = "Namespace for LangFuse."
  type        = string
  default     = "langfuse"
}

variable "langfuse_chart_version" {
  description = "LangFuse Helm chart version."
  type        = string
  default     = "1.2.18"
}

variable "langfuse_postgres_storage_class" {
  description = "StorageClass for LangFuse persistence. Empty string uses the cluster default."
  type        = string
  default     = "efs-sc"
}
