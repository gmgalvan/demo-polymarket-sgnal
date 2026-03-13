variable "role_name" {
  description = "The name of the IAM role for AWS Lambda."
  type        = string
  default     = "LambdaServiceRole"
}

variable "role_description" {
  description = "Description for the IAM role."
  type        = string
  default     = "IAM role assumed by AWS Lambda functions"
}

variable "ecr_policy_name" {
  description = "Name for the ECR access policy."
  type        = string
  default     = "LambdaECRReadOnlyAccess"
}

variable "ecr_policy_description" {
  description = "Description for the ECR access policy."
  type        = string
  default     = "Permissions for AWS Lambda to pull images from Amazon ECR"
}

variable "ecr_policy_resource" {
  description = "ECR repositories the policy applies to."
  type        = string
  default     = "*"
}

variable "bucket_arn" {
  description = "The s3 bucket the lambda role will be allowed to access"
}

variable "s3_lambda_access_policy_name" {
  description = "Name of the S3 access policy for AWS Lambda."
  type        = string
  default     = "S3LambdaAccess"
}

variable "texttrack_lambda_access_policy_name" {
  description = "S3 access policy for Texttrack."
  type        = string
  default     = "Permissions for AWS Lambda to Texttrackt"
}

variable "enable_textract_policy" {
  description = "Whether to create the Textract IAM policy and attachment"
  type        = bool
  default     = false
}

variable "ec2_policy_name" {
  description = "Name for the EC2 access policy."
  type        = string
  default     = "LambdaEC2Access"
}

variable "ec2_policy_description" {
  description = "Description for the EC2 access policy."
  type        = string
  default     = "Permissions for AWS Lambda to pull images from Amazon EC2"
}