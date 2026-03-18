variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag value."
  type        = string
  default     = "352-demo"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "dev"
}

# ── OpenSearch ─────────────────────────────────────────────────────────────────
variable "domain_name" {
  description = "OpenSearch domain name."
  type        = string
  default     = "352-demo-dev-vectordb"
}

variable "engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "2.13"
}

variable "instance_type" {
  description = "OpenSearch node instance type."
  type        = string
  # t3.medium.search: cheap for dev (no k-NN dedicated master needed at this size)
  # r6g.large.search: production (memory-optimized, Graviton2)
  default = "t3.medium.search"
}

variable "instance_count" {
  description = "Number of OpenSearch data nodes."
  type        = number
  default     = 1
}

variable "ebs_volume_size_gb" {
  description = "EBS volume size in GiB per node."
  type        = number
  default     = 20
}

variable "master_user_arn" {
  description = "IAM role ARN granted master-user access on the domain (e.g. an admin role or the deployer role)."
  type        = string
}

# ── IRSA / K8s ────────────────────────────────────────────────────────────────
variable "agent_namespace" {
  description = "Kubernetes namespace where agent pods run."
  type        = string
  default     = "default"
}

variable "agent_service_account" {
  description = "Kubernetes service account name used by agent pods."
  type        = string
  default     = "polymarket-agent"
}

# ── Remote state pointers ──────────────────────────────────────────────────────
variable "vpc_state_bucket" {
  type    = string
  default = "352-demo-dev-s3b-tfstate-backend"
}

variable "vpc_state_key" {
  type    = string
  default = "dev/lv-0-networking/vpc/terraform.tfstate"
}

variable "vpc_state_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_state_bucket" {
  type    = string
  default = "352-demo-dev-s3b-tfstate-backend"
}

variable "eks_state_key" {
  type    = string
  default = "dev/lv-2-core-compute/eks/terraform.tfstate"
}

variable "eks_state_region" {
  type    = string
  default = "us-east-1"
}

variable "additional_tags" {
  type = map(string)
  default = {
    ManagedBy  = "terraform"
    StackLevel = "level-2-core-compute"
    Owner      = "devops-team"
  }
}
