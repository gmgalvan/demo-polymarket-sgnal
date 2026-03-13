variable "aws_region" {
  description = "AWS region where EKS resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag value applied to resources."
  type        = string
  default     = "352-demo"
}

variable "environment" {
  description = "Environment tag value applied to resources."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "352-demo-dev-eks"
}

variable "cluster_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.30"
}

variable "eks_endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible."
  type        = bool
  default     = true
}

variable "vpc_state_bucket" {
  description = "S3 bucket containing lv-0 VPC Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "vpc_state_key" {
  description = "S3 key for lv-0 networking VPC Terraform state."
  type        = string
  default     = "dev/lv-0-networking/vpc/terraform.tfstate"
}

variable "vpc_state_region" {
  description = "Region where lv-0 VPC remote state backend lives."
  type        = string
  default     = "us-east-1"
}

variable "core_node_instance_type" {
  description = "Instance type for the default core managed node group."
  type        = string
  default     = "t3.large"
}

variable "core_node_min_size" {
  description = "Minimum nodes for the core managed node group."
  type        = number
  default     = 1
}

variable "core_node_desired_size" {
  description = "Desired nodes for the core managed node group."
  type        = number
  default     = 1
}

variable "core_node_max_size" {
  description = "Maximum nodes for the core managed node group."
  type        = number
  default     = 2
}

variable "l40s_instance_type" {
  description = "L40S-capable EC2 instance type for the GPU node group."
  type        = string
  default     = "g6e.xlarge"
}

variable "l40s_node_min_size" {
  description = "Minimum nodes for the L40S managed node group."
  type        = number
  default     = 1
}

variable "l40s_node_desired_size" {
  description = "Desired nodes for the L40S managed node group."
  type        = number
  default     = 1
}

variable "l40s_node_max_size" {
  description = "Maximum nodes for the L40S managed node group."
  type        = number
  default     = 1
}

variable "l40s_node_disk_size" {
  description = "Root volume size in GiB for L40S GPU worker nodes."
  type        = number
  default     = 200
}

variable "inferentia_instance_type" {
  description = "Inferentia-capable EC2 instance type for the Neuron node group."
  type        = string
  default     = "inf2.xlarge"
}

variable "inferentia_node_min_size" {
  description = "Minimum nodes for the Inferentia managed node group."
  type        = number
  default     = 1
}

variable "inferentia_node_desired_size" {
  description = "Desired nodes for the Inferentia managed node group."
  type        = number
  default     = 1
}

variable "inferentia_node_max_size" {
  description = "Maximum nodes for the Inferentia managed node group."
  type        = number
  default     = 1
}

variable "inferentia_node_disk_size" {
  description = "Root volume size in GiB for Inferentia worker nodes."
  type        = number
  default     = 150
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

variable "additional_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    StackLevel = "level-2-core-compute"
    Owner      = "devops-team"
  }
}
