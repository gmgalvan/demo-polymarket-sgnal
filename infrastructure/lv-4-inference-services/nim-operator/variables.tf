variable "aws_region" {
  description = "AWS region."
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

variable "nim_operator_chart_version" {
  description = "NVIDIA NIM Operator Helm chart version."
  type        = string
  default     = "1.0.0"
}

variable "nim_operator_namespace" {
  description = "Namespace where the NIM Operator is installed."
  type        = string
  default     = "nim-operator"
}

variable "ngc_api_key" {
  description = "NVIDIA NGC API key. Required to pull NIM container images from nvcr.io."
  type        = string
  sensitive   = true
}
