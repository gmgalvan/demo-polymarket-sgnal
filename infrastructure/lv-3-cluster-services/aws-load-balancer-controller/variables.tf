variable "aws_region" {
  description = "AWS region where EKS and the controller are managed."
  type        = string
  default     = "us-east-1"
}

variable "eks_state_bucket" {
  description = "S3 bucket containing the lv-2 EKS Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "eks_state_key" {
  description = "S3 key containing the lv-2 EKS Terraform state."
  type        = string
  default     = "dev/lv-2-core-compute/eks/terraform.tfstate"
}

variable "eks_state_region" {
  description = "AWS region containing the lv-2 EKS Terraform state."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for AWS Load Balancer Controller."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Kubernetes service account used by AWS Load Balancer Controller."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "chart_version" {
  description = "Pinned AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "3.3.0"
}

variable "replica_count" {
  description = "Number of AWS Load Balancer Controller replicas."
  type        = number
  default     = 2

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}

variable "node_selector" {
  description = "Node selector for controller Pods."
  type        = map(string)
  default = {
    workload = "core"
  }
}

variable "enable_service_mutator_webhook" {
  description = "Whether the controller mutates new LoadBalancer Services to use AWS LBC."
  type        = bool
  default     = false
}
