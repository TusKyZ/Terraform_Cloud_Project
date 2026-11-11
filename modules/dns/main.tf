locals {
  # CloudFront only uses ACM certificates from us-east-1, whatever Region the
  # rest of the stack is in.
  cloudfront_certificate_region = "us-east-1"
}

# The public hosted zone for the site's domain. Route 53 answers for the
# domain once its registrar lists this zone's name servers.
resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = {
    Name = "${var.name_prefix}-zone"
  }
}

# Certificate for the names viewers use, the apex and www, which CloudFront
# serves.
resource "aws_acm_certificate" "cloudfront" {
  region                    = local.cloudfront_certificate_region
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Name = "${var.name_prefix}-cloudfront-cert"
  }

  # ACM cannot delete a certificate that CloudFront or the ALB still uses, so
  # a replacement is created first and the old one deleted after the switch.
  lifecycle {
    create_before_destroy = true
  }
}

# Certificate for origin.<domain>, the name CloudFront uses to reach the ALB.
# It stays in the stack's Region, with the ALB.
resource "aws_acm_certificate" "alb" {
  domain_name       = "origin.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.name_prefix}-alb-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ACM issues a certificate once it finds, for each name on it, a CNAME record
# that ACM chose. The map is keyed by domain name, which Terraform knows when
# it plans; the record names and values come from ACM.
resource "aws_route53_record" "validation" {
  for_each = merge(
    { for option in aws_acm_certificate.cloudfront.domain_validation_options : option.domain_name => option },
    { for option in aws_acm_certificate.alb.domain_validation_options : option.domain_name => option },
  )

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

# These wait until ACM has issued each certificate (75 minutes at most by
# default). The certificate outputs come from them, so the ALB and CloudFront
# wait too. The validation looks the certificate up in ACM, so it runs in the
# certificate's Region.
resource "aws_acm_certificate_validation" "cloudfront" {
  region          = local.cloudfront_certificate_region
  certificate_arn = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [
    for option in aws_acm_certificate.cloudfront.domain_validation_options :
    aws_route53_record.validation[option.domain_name].fqdn
  ]
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn = aws_acm_certificate.alb.arn
  validation_record_fqdns = [
    for option in aws_acm_certificate.alb.domain_validation_options :
    aws_route53_record.validation[option.domain_name].fqdn
  ]
}
