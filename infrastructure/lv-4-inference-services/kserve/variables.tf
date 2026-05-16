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

variable "kserve_chart_version" {
  description = "KServe Helm chart version."
  type        = string
  default     = "v0.13.0"
}

variable "kserve_namespace" {
  description = "Namespace where KServe is installed."
  type        = string
  default     = "kserve"
}
