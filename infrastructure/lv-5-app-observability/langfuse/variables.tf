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

variable "langfuse_postgres_password" {
  description = "Password for the LangFuse PostgreSQL database."
  type        = string
  sensitive   = true
  default     = "langfuse-dev-password"
}

variable "langfuse_nextauth_secret" {
  description = "NextAuth secret for LangFuse session encryption."
  type        = string
  sensitive   = true
  default     = "langfuse-nextauth-secret-change-me"
}

variable "langfuse_salt" {
  description = "Salt for LangFuse API key hashing."
  type        = string
  sensitive   = true
  default     = "langfuse-salt-change-me"
}

variable "langfuse_postgres_storage_class" {
  description = "StorageClass for LangFuse persistence. Empty string uses the cluster default."
  type        = string
  default     = "efs-sc"
}
