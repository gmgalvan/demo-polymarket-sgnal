variable "aws_region" {
  description = "AWS region where networking resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Base name for the VPC and related resources."
  type        = string
  default     = "352-demo-dev-vpc"
}

variable "cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway for private subnets."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to create an S3 gateway endpoint in the VPC."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Whether to create VPC flow logs."
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default = {
    Project     = "352-demo"
    Environment = "dev"
    ManagedBy   = "terraform"
    StackLevel  = "level-0-networking"
    Owner       = "devops-team"
  }
}
