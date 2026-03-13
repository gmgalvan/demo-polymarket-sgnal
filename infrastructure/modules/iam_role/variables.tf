variable "name" {
  description = "The name of the IAM role."
  type        = string
}

variable "assume_role_policies" {
  description = "The assume role policy in JSON format."
  type        = string
}

variable "inline_policies" {
  description = "A list of inline policies to attach to the role."
  type        = list(map(string))
  default     = []
}

variable "policy_arns" {
  description = "A list of managed policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}