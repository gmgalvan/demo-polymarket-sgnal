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

variable "logging_namespace" {
  description = "Namespace for Loki and Fluent Bit."
  type        = string
  default     = "logging"
}

variable "enable_service_monitor" {
  description = "Enable ServiceMonitor resources in Helm charts for Prometheus scraping."
  type        = bool
  default     = true
}

variable "loki_chart_version" {
  description = "Loki Helm chart version."
  type        = string
  default     = "6.29.0"
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit Helm chart version."
  type        = string
  default     = "0.49.1"
}

variable "loki_storage_class" {
  description = "StorageClass for Loki PVC. Empty string uses the cluster default."
  type        = string
  default     = "efs-sc"
}
