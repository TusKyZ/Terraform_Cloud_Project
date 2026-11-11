output "alb_certificate_arn" {
  description = "ARN of the certificate for the origin name, such as origin.webschool.example, for the ALB's HTTPS listener. It comes from the validation, so anything that uses it waits until ACM has issued the certificate."
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "ARN of the us-east-1 certificate for the apex and www, for CloudFront. It comes from the validation, so anything that uses it waits until ACM has issued the certificate."
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "name_servers" {
  description = "Name servers of the hosted zone. The domain's registrar must list them before ACM can validate the certificates."
  value       = aws_route53_zone.this.name_servers
}

output "zone_id" {
  description = "ID of the public hosted zone, for the site's DNS records."
  value       = aws_route53_zone.this.zone_id
}
