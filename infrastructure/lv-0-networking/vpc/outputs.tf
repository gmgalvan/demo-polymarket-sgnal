output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr
}

output "availability_zones" {
  description = "The 3 selected AZs used by this stack."
  value       = local.selected_azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (3 total, one per AZ)."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (6 total, two per AZ)."
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = module.vpc.nat_gateway_ids
}

