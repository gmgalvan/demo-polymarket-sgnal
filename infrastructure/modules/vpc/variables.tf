variable "name" {
  description = "The name of the Terraform stack, e.g. \"example-dbt\""
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "public_subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets to create"
  type        = number
  default     = 2
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "additional_subnet_count" {
  type    = number
  default = 0
}

variable "additional_subnet_newbits" {
  type    = number
  default = 8 # This creates /24 subnets if your VPC is /16 (16+8=24)
}

variable "enable_nat_gateway_for_additional_private" {
  description = "Whether to enable NAT Gateway for private additional subnets"
  type        = bool
  default     = false
}

variable "enable_s3_gateway_endpoint" {
  description = "Whether to enable S3 Gateway Endpoint for private subnets"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for aws_vpc.main"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention for VPC Flow Logs"
  type        = number
  default     = 3
}

variable "flow_logs_aggregation_interval" {
  description = "Max aggregation interval in seconds (allowed: 60 or 600)"
  type        = number
  default     = 600
}

variable "map_public_ip_on_launch" {
  description = "Whether to assign public IPs to instances launched in public subnets"
  type        = bool
  default     = true
}