variable "aws_region" {
  description = "The AWS region where the SSM parameters will be created"
  type        = string
}

variable "solution" {
  description = "The solution identifier (sol) used in parameter paths"
  type        = string
}

variable "tenant" {
  description = "The tenant identifier (ten) used in parameter paths"
  type        = string
}

variable "environment" {
  description = "The environment identifier used in parameter paths (e.g., dev, staging, prod). Defaults to 'general' if not provided."
  type        = string
  default     = null
}

variable "yaml_file" {
  description = "Path to the YAML file containing configuration"
  type        = string
}
