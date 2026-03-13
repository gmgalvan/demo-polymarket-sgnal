variable "aws_region" {
  description = "AWS region where EKS and Karpenter resources are managed."
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

variable "karpenter_namespace" {
  description = "Namespace where Karpenter will be installed."
  type        = string
  default     = "kube-system"
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm chart version. Set null to use latest chart."
  type        = string
  default     = null
  nullable    = true
}

variable "install_nvidia_device_plugin" {
  description = "Whether to install NVIDIA device plugin."
  type        = bool
  default     = true
}

variable "install_neuron_device_plugin" {
  description = "Whether to install AWS Neuron device plugin."
  type        = bool
  default     = true
}

variable "enable_karpenter_nodepools" {
  description = "Whether to install EC2NodeClass and NodePool resources."
  type        = bool
  default     = true
}
