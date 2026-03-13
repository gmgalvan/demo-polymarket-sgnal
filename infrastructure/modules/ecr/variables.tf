variable "repository_name" {
  type        = string
  description = "Name of the ECR repository"
}

variable "scan_on_push" {
  type        = bool
  description = "Whether to scan on push"
}


variable "tags" {
  type        = map(string)
  description = "Tags to apply to the ECR repository"
  default     = {}
}
