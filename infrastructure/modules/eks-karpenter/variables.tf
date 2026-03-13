variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint."
  type        = string
}

variable "karpenter_iam_role_arn" {
  description = "IAM role ARN used by Karpenter service account."
  type        = string
}

variable "karpenter_interruption_queue_name" {
  description = "SQS queue name used by Karpenter interruption handling."
  type        = string
}

variable "karpenter_namespace" {
  description = "Namespace where Karpenter will be installed."
  type        = string
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm chart version. Set null to use latest chart."
  type        = string
  default     = null
  nullable    = true
}
