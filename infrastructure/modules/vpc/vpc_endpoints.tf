# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  count        = var.enable_s3_gateway_endpoint ? 1 : 0
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = compact([
    aws_default_route_table.private.id,
    length(aws_route_table.private_additional) > 0 ? aws_route_table.private_additional[0].id : ""
  ])

  tags = merge(local.common_tags, {
    Name = "${var.name}-s3-gateway-endpoint"
  })
}