variable "plugin_namespace" {
  description = "Namespace where the AWS Neuron device plugin is installed."
  type        = string
  default     = "kube-system"
}
