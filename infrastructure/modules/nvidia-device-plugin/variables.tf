variable "plugin_namespace" {
  description = "Namespace where the NVIDIA device plugin is installed."
  type        = string
  default     = "kube-system"
}
