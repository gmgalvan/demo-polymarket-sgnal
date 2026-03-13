variable "iam_lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function."
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function without the environment suffix."
  type        = string
}

variable "docker_image_uri" {
  description = "Docker image URI for the Lambda function."
  type        = string
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds."
  type        = number
  default     = 150
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB."
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs."
  type        = number
  default     = 14
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "ephemeral_storage" {
  description = "Ephemeral storage for the Lambda function"
  type        = number
  default     = 512
}

variable "file_system_arn" {
  description = "The filesystem arn if any to attach to the lambda function"
  type        = string
  default     = ""
}

variable "file_system_local_mount_path" {
  description = "The mount path to attach the filesystem to"
  type        = string
  default     = "/mnt/tmp"
}

variable "vpc_config" {
  description = "The VPC configuration for the Lambda function"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "invoke_permissions" {
  description = "List of permissions to allow various services to invoke the Lambda function"
  type = list(object({
    statement_id = string # Identifier for the statement
    principal    = string # The AWS service (e.g., "s3.amazonaws.com", "apigateway.amazonaws.com", etc.)
    source_arn   = string # The ARN of the source resource invoking the Lambda function (e.g., "arn:aws:s3:::my-bucket")
  }))
  default = []
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "tags" {
  description = "Lambda tags to identify"
  type        = map(string)
  default     = null
}

variable "description" {
  description = "Describe what the lambda does"
  type        = string
  default     = null
}

variable "image_config" {
  description = "image_config overrides"
  type = object({
    command           = list(string)
    entry_point       = list(string)
    working_directory = string
  })
  default = null
}
