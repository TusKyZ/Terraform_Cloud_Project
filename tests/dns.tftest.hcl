# Unit tests for modules/dns. They plan against a mock AWS provider, so they
# need no AWS credentials and create nothing.

mock_provider "aws" {}

variables {
  domain_name = "webschool.example"
  name_prefix = "web-school-prod"
}

# The mock provider cannot know which DNS records ACM will ask for, and the
# module creates one validation record per domain name from them. So every
# run gives both certificates fixed fake ARNs and validation details.
override_resource {
  target          = aws_acm_certificate.cloudfront
  override_during = plan
  values = {
    arn = "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test"
    domain_validation_options = [
      {
        domain_name           = "webschool.example"
        resource_record_name  = "_apex.webschool.example."
        resource_record_type  = "CNAME"
        resource_record_value = "_apex.acm-validations.aws."
      },
      {
        domain_name           = "www.webschool.example"
        resource_record_name  = "_www.www.webschool.example."
        resource_record_type  = "CNAME"
        resource_record_value = "_www.acm-validations.aws."
      },
    ]
  }
}

override_resource {
  target          = aws_acm_certificate.alb
  override_during = plan
  values = {
    arn = "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
    domain_validation_options = [
      {
        domain_name           = "origin.webschool.example"
        resource_record_name  = "_origin.origin.webschool.example."
        resource_record_type  = "CNAME"
        resource_record_value = "_origin.acm-validations.aws."
      },
    ]
  }
}

run "zone_is_public_and_for_the_domain" {
  command = plan

  module {
    source = "./modules/dns"
  }

  assert {
    condition     = aws_route53_zone.this.name == "webschool.example"
    error_message = "The hosted zone must be for domain_name."
  }

  # A zone with a VPC attached is private and answers only inside that VPC.
  assert {
    condition     = length(aws_route53_zone.this.vpc) == 0
    error_message = "The hosted zone must be public, with no VPC attached."
  }

  assert {
    condition     = aws_route53_zone.this.tags["Name"] == "web-school-prod-zone"
    error_message = "The hosted zone's Name tag must be <name_prefix>-zone."
  }
}

run "cloudfront_certificate_is_in_us_east_1_for_the_apex_and_www" {
  command = plan

  module {
    source = "./modules/dns"
  }

  # CloudFront only uses ACM certificates from us-east-1.
  assert {
    condition     = aws_acm_certificate.cloudfront.region == "us-east-1"
    error_message = "The CloudFront certificate must be in us-east-1."
  }

  assert {
    condition = (
      aws_acm_certificate.cloudfront.domain_name == "webschool.example" &&
      aws_acm_certificate.cloudfront.subject_alternative_names == toset(["www.webschool.example"])
    )
    error_message = "The CloudFront certificate must cover the apex and www."
  }

  assert {
    condition     = aws_acm_certificate.cloudfront.validation_method == "DNS"
    error_message = "The CloudFront certificate must be validated through DNS."
  }

  assert {
    condition     = aws_acm_certificate.cloudfront.tags["Name"] == "web-school-prod-cloudfront-cert"
    error_message = "The CloudFront certificate's Name tag must be <name_prefix>-cloudfront-cert."
  }
}

run "alb_certificate_is_for_the_origin_name" {
  command = plan

  module {
    source = "./modules/dns"
  }

  # CloudFront connects to the ALB as origin.<domain>, so the ALB's
  # certificate must be for that name.
  assert {
    condition     = aws_acm_certificate.alb.domain_name == "origin.webschool.example"
    error_message = "The ALB certificate must be for origin.<domain_name>."
  }

  assert {
    condition     = aws_acm_certificate.alb.validation_method == "DNS"
    error_message = "The ALB certificate must be validated through DNS."
  }

  assert {
    condition     = aws_acm_certificate.alb.tags["Name"] == "web-school-prod-alb-cert"
    error_message = "The ALB certificate's Name tag must be <name_prefix>-alb-cert."
  }
}

run "each_domain_name_gets_its_validation_record_in_the_zone" {
  command = plan

  module {
    source = "./modules/dns"
  }

  override_resource {
    target          = aws_route53_zone.this
    override_during = plan
    values = {
      zone_id = "Z0TEST"
    }
  }

  # One record per domain name on either certificate, with the name, type
  # and value that ACM asked for.
  assert {
    condition = toset([
      for domain, record in aws_route53_record.validation :
      "${domain} ${record.zone_id} ${record.name} ${record.type} ${one(record.records)} ${record.ttl}"
      ]) == toset([
      "webschool.example Z0TEST _apex.webschool.example. CNAME _apex.acm-validations.aws. 60",
      "www.webschool.example Z0TEST _www.www.webschool.example. CNAME _www.acm-validations.aws. 60",
      "origin.webschool.example Z0TEST _origin.origin.webschool.example. CNAME _origin.acm-validations.aws. 60",
    ])
    error_message = "Every domain name on both certificates must get the CNAME record that ACM asked for, in the hosted zone."
  }
}

run "each_validation_waits_for_its_own_certificate_and_records" {
  command = plan

  module {
    source = "./modules/dns"
  }

  # Fixed fake FQDNs, so each validation's records can be checked.
  override_resource {
    target          = aws_route53_record.validation["webschool.example"]
    override_during = plan
    values = {
      fqdn = "_apex.webschool.example"
    }
  }

  override_resource {
    target          = aws_route53_record.validation["www.webschool.example"]
    override_during = plan
    values = {
      fqdn = "_www.www.webschool.example"
    }
  }

  override_resource {
    target          = aws_route53_record.validation["origin.webschool.example"]
    override_during = plan
    values = {
      fqdn = "_origin.origin.webschool.example"
    }
  }

  assert {
    condition = (
      aws_acm_certificate_validation.cloudfront.certificate_arn == "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test" &&
      aws_acm_certificate_validation.cloudfront.validation_record_fqdns == toset(["_apex.webschool.example", "_www.www.webschool.example"])
    )
    error_message = "The CloudFront certificate's validation must wait for that certificate's apex and www records."
  }

  assert {
    condition = (
      aws_acm_certificate_validation.alb.certificate_arn == "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test" &&
      aws_acm_certificate_validation.alb.validation_record_fqdns == toset(["_origin.origin.webschool.example"])
    )
    error_message = "The ALB certificate's validation must wait for the origin record."
  }

  # The validation looks the certificate up in ACM, which only finds a
  # certificate in its own Region.
  assert {
    condition     = aws_acm_certificate_validation.cloudfront.region == "us-east-1"
    error_message = "The CloudFront certificate's validation must be in us-east-1, like the certificate."
  }
}

run "outputs_are_the_zone_and_the_validated_certificates" {
  command = plan

  module {
    source = "./modules/dns"
  }

  override_resource {
    target          = aws_route53_zone.this
    override_during = plan
    values = {
      zone_id      = "Z0TEST"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"]
    }
  }

  # name_servers is a list, and == also compares types, so the expected value
  # must be a list too, not a tuple literal.
  assert {
    condition = (
      output.zone_id == "Z0TEST" &&
      output.name_servers == tolist(["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"])
    )
    error_message = "zone_id and name_servers must come from the hosted zone."
  }

  assert {
    condition = (
      output.cloudfront_certificate_arn == "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test" &&
      output.alb_certificate_arn == "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
    )
    error_message = "Each certificate output must be the ARN of its own certificate."
  }
}

run "domain_name_with_a_scheme_is_rejected" {
  command = plan

  module {
    source = "./modules/dns"
  }

  variables {
    domain_name = "https://webschool.example"
  }

  expect_failures = [var.domain_name]
}

run "domain_name_with_a_trailing_dot_is_rejected" {
  command = plan

  module {
    source = "./modules/dns"
  }

  variables {
    domain_name = "webschool.example."
  }

  expect_failures = [var.domain_name]
}

run "uppercase_domain_name_is_rejected" {
  command = plan

  module {
    source = "./modules/dns"
  }

  variables {
    domain_name = "WebSchool.example"
  }

  expect_failures = [var.domain_name]
}

# No wildcard certificates (checkov CKV2_AWS_71): each certificate names
# the hosts it covers.
run "wildcard_domain_name_is_rejected" {
  command = plan

  module {
    source = "./modules/dns"
  }

  variables {
    domain_name = "*.webschool.example"
  }

  expect_failures = [var.domain_name]
}
