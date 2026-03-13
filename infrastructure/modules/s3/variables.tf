variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket."
  type        = string
}

variable "enabled_eventbridge" {
  description = "Boolean to enable eventbridge"
  type        = bool
  default     = false
}

variable "s3_bucket_objects" {
  description = "Map of S3 object keys to their source file paths"
  type = list(object({
    source = string
    key    = string
  }))
  default = []
}

variable "s3_bucket_update_objects" {
  description = "Map of S3 object keys to their source file paths"
  type = list(object({
    source = string
    key    = string
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to add to s3 bucket"
  type        = map(string)
  default     = {}
}

variable "allow_transfer_acceleration" {
  description = "Boolean to enable transfer acceleration"
  type        = bool
  default     = false
}

variable "cors_rules" {
  description = "List of maps containing CORS configuration rules"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  }))
  default = []
}
