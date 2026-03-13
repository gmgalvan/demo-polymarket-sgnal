variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "EKS control plane version."
  type        = string
}

variable "eks_endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible."
  type        = bool
}

variable "vpc_id" {
  description = "VPC ID where EKS resources will be created."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs used by EKS."
  type        = list(string)
}

variable "core_node_instance_type" {
  description = "Instance type for the default core managed node group."
  type        = string
}

variable "core_node_ami_type" {
  description = "AMI type for the default core managed node group."
  type        = string
}

variable "core_node_min_size" {
  description = "Minimum nodes for the core managed node group."
  type        = number
}

variable "core_node_desired_size" {
  description = "Desired nodes for the core managed node group."
  type        = number
}

variable "core_node_max_size" {
  description = "Maximum nodes for the core managed node group."
  type        = number
}

variable "l40s_instance_type" {
  description = "L40S-capable EC2 instance type for the GPU node group."
  type        = string
}

variable "l40s_node_min_size" {
  description = "Minimum nodes for the L40S managed node group."
  type        = number
}

variable "l40s_node_desired_size" {
  description = "Desired nodes for the L40S managed node group."
  type        = number
}

variable "l40s_node_max_size" {
  description = "Maximum nodes for the L40S managed node group."
  type        = number
}

variable "l40s_node_disk_size" {
  description = "Root volume size in GiB for L40S GPU worker nodes."
  type        = number
}

variable "inferentia_instance_type" {
  description = "Inferentia-capable EC2 instance type for the Neuron node group."
  type        = string
}

variable "inferentia_node_min_size" {
  description = "Minimum nodes for the Inferentia managed node group."
  type        = number
}

variable "inferentia_node_desired_size" {
  description = "Desired nodes for the Inferentia managed node group."
  type        = number
}

variable "inferentia_node_max_size" {
  description = "Maximum nodes for the Inferentia managed node group."
  type        = number
}

variable "inferentia_node_disk_size" {
  description = "Root volume size in GiB for Inferentia worker nodes."
  type        = number
}

variable "karpenter_namespace" {
  description = "Namespace where Karpenter will be installed."
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to EKS and Karpenter resources."
  type        = map(string)
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs that should have EKS cluster admin access via access entries."
  type        = list(string)
  default     = []
}
