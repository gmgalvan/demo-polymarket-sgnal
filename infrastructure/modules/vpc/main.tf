locals {
  common_tags = merge(
    {
      Name = var.name
    },
    var.additional_tags
  )

  # Reserve netnums 0 to (public_subnet_count + private_subnet_count - 1) for the original subnets.
  # Allocate additional PUBLIC subnets after those original subnets.
  public_additional_subnet_cidrs = [
    for i in range(var.additional_subnet_count) :
    cidrsubnet(var.cidr, var.additional_subnet_newbits, i + var.public_subnet_count + var.private_subnet_count)
  ]

  # Allocate additional PRIVATE subnets after the original subnets and the additional public ones.
  private_additional_subnet_cidrs = [
    for i in range(var.additional_subnet_count) :
    cidrsubnet(var.cidr, var.additional_subnet_newbits, i + var.public_subnet_count + var.private_subnet_count + var.additional_subnet_count)
  ]
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name}"
  })
}

# DHCP Options Set
resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "${var.aws_region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = merge(local.common_tags, {
    Name = "${var.name}-dhcp-options"
  })
}

# Associate DHCP Options with VPC
resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-igw"
  })
}

# Primary NAT Gateway for original private subnets
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat"
  })
}

# NAT Gateway for additional private subnets (if enabled)
resource "aws_nat_gateway" "additional" {
  count         = var.enable_nat_gateway_for_additional_private ? 1 : 0
  allocation_id = aws_eip.nat_additional[0].id
  subnet_id     = length(aws_subnet.public) > 0 ? aws_subnet.public[0].id : aws_subnet.public_additional[0].id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-additional"
  })
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-eip"
  })
}

resource "aws_eip" "nat_additional" {
  count  = var.enable_nat_gateway_for_additional_private ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-eip-additional"
  })
}

# Original Public Subnets
resource "aws_subnet" "public" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.cidr, 8, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-subnet-${format("%03d", count.index + 1)}"
  })
}

# Original Private Subnets
resource "aws_subnet" "private" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr, 8, count.index + var.public_subnet_count)
  availability_zone = element(var.availability_zones, count.index)

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-subnet-${format("%03d", count.index + 1)}"
  })
}

# Additional Public Subnets
resource "aws_subnet" "public_additional" {
  count                   = length(local.public_additional_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_additional_subnet_cidrs[count.index]
  availability_zone       = element(var.availability_zones, count.index % length(var.availability_zones))
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-additional-subnet-${format("%03d", count.index + 1)}"
  })
}

# Additional Private Subnets
resource "aws_subnet" "private_additional" {
  count             = length(local.private_additional_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_additional_subnet_cidrs[count.index]
  availability_zone = element(var.availability_zones, count.index % length(var.availability_zones))

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-additional-subnet-${format("%03d", count.index + 1)}"
  })
}

# Public Route Table & Associations
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-routing-table-public"
  })
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = var.public_subnet_count
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

# Create a dedicated route table for additional public subnets
resource "aws_route_table" "public_additional" {
  count  = length(local.public_additional_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-routing-table-public-additional"
  })
}

# Add internet route for additional public route table
resource "aws_route" "public_additional" {
  count                  = length(local.public_additional_subnet_cidrs) > 0 ? 1 : 0
  route_table_id         = aws_route_table.public_additional[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate additional public subnets with their dedicated public route table
resource "aws_route_table_association" "public_additional" {
  count          = length(aws_subnet.public_additional)
  subnet_id      = aws_subnet.public_additional[count.index].id
  route_table_id = aws_route_table.public_additional[0].id
}

# Private Default Route Table & Associations
resource "aws_default_route_table" "private" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = merge(local.common_tags, {
    Name = "${var.name}-routing-table-private"
  })
}

# Route for original private subnets via NAT Gateway
resource "aws_route" "private" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_default_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "private" {
  count          = var.private_subnet_count
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = aws_default_route_table.private.id
}

# Route table for additional private subnets
resource "aws_route_table" "private_additional" {
  count  = length(local.private_additional_subnet_cidrs) > 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-routing-table-private-additional"
  })
}

# Route for additional private subnets via dedicated NAT Gateway (if enabled)
resource "aws_route" "private_additional" {
  count                  = var.enable_nat_gateway_for_additional_private ? 1 : 0
  route_table_id         = aws_route_table.private_additional[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.additional[0].id
}

# Associate additional private subnets with their route table
resource "aws_route_table_association" "private_additional" {
  count          = length(aws_subnet.private_additional)
  subnet_id      = aws_subnet.private_additional[count.index].id
  route_table_id = aws_route_table.private_additional[0].id
}

# ---- CloudWatch Logs log group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "main" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.name}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  tags              = local.common_tags
}

# ---- IAM trust policy (VPC Flow Logs service principal)
data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ---- IAM role for Flow Logs to publish to CloudWatch Logs
resource "aws_iam_role" "vpc_flow_logs_role" {
  count              = var.enable_flow_logs ? 1 : 0
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role.json
  tags               = local.common_tags
}

# ---- IAM permissions required by Flow Logs to write logs
data "aws_iam_policy_document" "vpc_flow_logs_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  count  = var.enable_flow_logs ? 1 : 0
  name   = "${var.name}-vpc-flow-logs"
  role   = aws_iam_role.vpc_flow_logs_role[0].id
  policy = data.aws_iam_policy_document.vpc_flow_logs_permissions.json
}

# ---- The actual VPC Flow Log
resource "aws_flow_log" "main" {
  count                    = var.enable_flow_logs ? 1 : 0
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.main[0].arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs_role[0].arn
  max_aggregation_interval = var.flow_logs_aggregation_interval
  tags                     = local.common_tags
}
