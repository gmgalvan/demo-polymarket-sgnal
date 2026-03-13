data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "../../modules/vpc"

  name               = var.name
  aws_region         = var.aws_region
  cidr               = var.cidr
  availability_zones = local.selected_azs

  # 1 public subnet per AZ across 3 AZs.
  public_subnet_count = 3
  # 2 private subnets per AZ across 3 AZs (6 total).
  private_subnet_count = 6

  enable_nat_gateway         = var.enable_nat_gateway
  enable_s3_gateway_endpoint = var.enable_s3_gateway_endpoint
  enable_flow_logs           = var.enable_flow_logs
  additional_tags            = var.additional_tags
}

