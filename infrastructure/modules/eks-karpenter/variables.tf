variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "karpenter_instance_profile_name" {
  description = "Instance profile name used by Karpenter-launched nodes."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs that Karpenter can use for node launches."
  type        = list(string)
}

variable "cluster_primary_security_group_id" {
  description = "Cluster primary security group ID for Karpenter-launched nodes."
  type        = string
}

variable "node_security_group_id" {
  description = "Node security group ID for Karpenter-launched nodes."
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

variable "core_node_instance_type" {
  description = "Default instance type for the ARM/core Karpenter node pool."
  type        = string
}

variable "l40s_instance_type" {
  description = "Default instance type for the GPU Karpenter node pool."
  type        = string
}

variable "inferentia_instance_type" {
  description = "Default instance type for the Inferentia Karpenter node pool."
  type        = string
}

variable "install_nvidia_device_plugin" {
  description = "Whether to install the NVIDIA device plugin via Helm."
  type        = bool
  default     = true
}

variable "install_neuron_device_plugin" {
  description = "Whether to install the AWS Neuron device plugin via Helm."
  type        = bool
  default     = true
}

variable "enable_karpenter_nodepools" {
  description = "Whether to install Karpenter EC2NodeClass and NodePool resources after CRDs are available in the cluster."
  type        = bool
  default     = false
}
