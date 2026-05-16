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

variable "kuberay_chart_version" {
  description = "KubeRay operator Helm chart version."
  type        = string
  default     = "1.2.2"
}

variable "kuberay_namespace" {
  description = "Namespace where KubeRay operator is installed."
  type        = string
  default     = "kuberay-system"
}
