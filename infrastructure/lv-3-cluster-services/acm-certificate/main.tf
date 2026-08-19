locals {
  tags = {
    Project   = "demo-polymarket-signal"
    Layer     = "lv-3-cluster-services"
    Component = "acm-certificate"
    ManagedBy = "terraform"
  }
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = local.tags

  # DNS validation needs the new cert to exist alongside the old one
  # while Route53/ACM settle, so replacing (e.g. adding a SAN) doesn't
  # leave a window with no valid certificate at all.
  lifecycle {
    create_before_destroy = true
  }
}

# One CNAME per domain ACM needs proof-of-ownership for. Same
# hosted_zone_id external-dns is scoped to.
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

# Blocks until ACM actually sees the validation record and marks the
# certificate ISSUED - so anything depending on this layer's
# certificate_arn output can safely assume the cert is ready to use.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
