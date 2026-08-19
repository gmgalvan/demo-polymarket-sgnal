variable "aws_region" {
  description = "AWS region for the certificate (must match the ALB's region)."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain the certificate covers."
  type        = string
  default     = "finance.gmgalvan.com"
}

variable "subject_alternative_names" {
  description = "Extra domains covered by the same certificate."
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone where the DNS validation record is created. Same zone external-dns manages (gmgalvan.com)."
  type        = string
  default     = "Z08205913ACQUTWJH2PLJ"
}
