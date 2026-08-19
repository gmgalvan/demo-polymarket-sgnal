output "certificate_arn" {
  description = "ARN to put in the Ingress's alb.ingress.kubernetes.io/certificate-arn annotation. Depends on the validation resource, so it's only ever populated once the certificate is actually ISSUED."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "Domain the certificate covers."
  value       = aws_acm_certificate.this.domain_name
}

output "status" {
  description = "ACM certificate status (should be ISSUED after apply)."
  value       = aws_acm_certificate.this.status
}
