variable "aws_region" {
  description = "AWS region where EKS and ExternalDNS are managed."
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
  description = "Kubernetes namespace for ExternalDNS."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Kubernetes service account used by ExternalDNS."
  type        = string
  default     = "external-dns"
}

variable "chart_version" {
  description = "Pinned official ExternalDNS Helm chart version."
  type        = string
  default     = "1.21.1"
}

variable "hosted_zone_id" {
  description = "Public Route 53 hosted zone ID that ExternalDNS may update."
  type        = string
  default     = "Z08205913ACQUTWJH2PLJ"
}

variable "domain_filter" {
  description = "DNS suffix ExternalDNS is allowed to manage."
  type        = string
  default     = "gmgalvan.com"
}

variable "dns_policy" {
  description = "ExternalDNS record policy: upsert-only is safer; sync also deletes owned stale records."
  type        = string
  default     = "upsert-only"

  validation {
    condition     = contains(["upsert-only", "sync", "create-only"], var.dns_policy)
    error_message = "dns_policy must be upsert-only, sync, or create-only."
  }
}

variable "node_selector" {
  description = "Node selector for the ExternalDNS Pod."
  type        = map(string)
  default = {
    workload = "core"
  }
}
