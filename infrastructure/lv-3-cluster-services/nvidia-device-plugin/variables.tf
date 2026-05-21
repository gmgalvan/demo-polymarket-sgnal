variable "aws_region" {
  description = "AWS region where EKS and the NVIDIA device plugin are managed."
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

variable "plugin_namespace" {
  description = "Namespace where the NVIDIA device plugin is installed."
  type        = string
  default     = "kube-system"
}

variable "time_slicing_enabled" {
  description = "Whether to enable NVIDIA GPU time-slicing."
  type        = bool
  default     = false
}

variable "time_slicing_replicas" {
  description = "Logical GPU share count per physical GPU when time-slicing is enabled."
  type        = number
  default     = 4
}
