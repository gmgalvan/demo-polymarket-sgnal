variable "domain_name" {
  description = "OpenSearch domain name."
  type        = string
}

variable "engine_version" {
  description = "OpenSearch engine version (without 'OpenSearch_' prefix)."
  type        = string
  default     = "2.13"
}

variable "instance_type" {
  description = "OpenSearch instance type."
  type        = string
  default     = "t3.medium.search"
}

variable "instance_count" {
  description = "Number of data nodes."
  type        = number
  default     = 1
}

variable "ebs_volume_size_gb" {
  description = "EBS volume size in GiB per node."
  type        = number
  default     = 20
}

variable "vpc_id" {
  description = "VPC ID for the OpenSearch domain."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs where OpenSearch nodes will be placed (one per AZ if multi-node)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to reach OpenSearch on port 443 (EKS node/pod SGs)."
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for IRSA)."
  type        = string
}

variable "master_user_arn" {
  description = "IAM role ARN to be granted master-user access on the domain (e.g., the admin role)."
  type        = string
}

variable "agent_role_arn" {
  description = "IAM role ARN for the agent pods (added to access policy). Pass the output of this module after creation."
  type        = string
  default     = "*"
}

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

variable "common_tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
