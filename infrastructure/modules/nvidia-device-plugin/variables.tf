variable "plugin_namespace" {
  description = "Namespace where the NVIDIA device plugin is installed."
  type        = string
  default     = "kube-system"
}

variable "time_slicing_enabled" {
  description = "Whether to enable NVIDIA GPU time-slicing for shared GPU scheduling."
  type        = bool
  default     = false
}

variable "time_slicing_replicas" {
  description = "Number of logical GPU shares to advertise per physical GPU when time-slicing is enabled."
  type        = number
  default     = 4
}
