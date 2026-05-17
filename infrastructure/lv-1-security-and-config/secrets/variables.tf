variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix used in secret paths."
  type        = string
  default     = "352-demo"
}

variable "environment" {
  description = "Environment segment used in secret paths."
  type        = string
  default     = "dev"
}

variable "initial_secret_placeholder" {
  description = "Initial placeholder value written when a secret is first created."
  type        = string
  sensitive   = true
  default     = ""
}

variable "config_parameters" {
  description = "Optional non-secret SSM parameters to create."
  type        = map(string)
  default     = {}
}

variable "additional_tags" {
  description = "Additional tags to apply to created resources."
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    StackLevel = "level-1-security-and-config"
  }
}
