# Create the S3 bucket
resource "aws_s3_bucket" "this" {
  bucket = var.s3_bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0 # Only create if the CORS rules variable was passed in

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }
}

# Create the S3 bucket objects
resource "aws_s3_object" "this" {
  for_each = { for obj in var.s3_bucket_objects : obj.key => obj }

  bucket = var.s3_bucket_name
  acl    = "private"

  source = each.value.source
  key    = each.value.key

  depends_on = [aws_s3_bucket.this]
}

# Create the S3 bucket objects that need to be updated by terraform
resource "aws_s3_object" "update" {
  for_each = { for obj in var.s3_bucket_update_objects : obj.key => obj }

  bucket = var.s3_bucket_name
  acl    = "private"

  source = each.value.source
  key    = each.value.key

  etag = filemd5(each.value.source)

  depends_on = [aws_s3_bucket.this]
}

# Allow transfer acceleration
resource "aws_s3_bucket_accelerate_configuration" "this" {
  count  = var.allow_transfer_acceleration ? 1 : 0
  bucket = aws_s3_bucket.this.id
  status = "Enabled"

  depends_on = [aws_s3_bucket.this]
}