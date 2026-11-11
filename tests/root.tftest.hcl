# Tests for the root module: the values in terraform.tfvars reach the right
# module inputs, and each root output shows the right module's value. They
# plan against a mock AWS provider, so they need no AWS credentials and
# create nothing.

mock_provider "aws" {}

# The mock provider cannot know which DNS records ACM will ask for, and the
# dns module creates one validation record per domain name from them. So
# every run gives both certificates fixed fake ARNs and validation details.
override_resource {
  target          = module.dns.aws_acm_certificate.cloudfront
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
  target          = module.dns.aws_acm_certificate.alb
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

# The mock provider fills data sources with random strings, and the provider
# checks that a policy ARN is a valid ARN. So every run gets the real ARN of
# AWS's managed Session Manager policy.
override_data {
  target = module.compute.data.aws_iam_policy.ssm_core
  values = {
    arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

run "network_gets_each_tier_from_tfvars" {
  command = plan

  assert {
    condition     = local.name_prefix == "web-school-prod"
    error_message = "Names must start with <project>-<environment>, here web-school-prod."
  }

  # Each tier has its own CIDR blocks, so passing one tier's list to another
  # tier's input would show up.
  assert {
    condition = (
      module.network.public_subnet_cidrs == ["10.0.1.0/24", "10.0.2.0/24"] &&
      module.network.app_subnet_cidrs == ["10.0.11.0/24", "10.0.12.0/24"] &&
      module.network.db_subnet_cidrs == ["10.0.21.0/24", "10.0.22.0/24"]
    )
    error_message = "The network module must get each tier's subnet CIDR blocks from terraform.tfvars."
  }
}

run "security_module_gives_its_security_group_ids" {
  command = plan

  # Fixed fake IDs for the module's groups, so its outputs can be checked.
  override_resource {
    target          = module.security.aws_security_group.alb
    override_during = plan
    values = {
      id = "sg-0alb"
    }
  }

  override_resource {
    target          = module.security.aws_security_group.app
    override_during = plan
    values = {
      id = "sg-0app"
    }
  }

  override_resource {
    target          = module.security.aws_security_group.db
    override_during = plan
    values = {
      id = "sg-0db"
    }
  }

  assert {
    condition = (
      module.security.alb_sg_id == "sg-0alb" &&
      module.security.app_sg_id == "sg-0app" &&
      module.security.db_sg_id == "sg-0db"
    )
    error_message = "The root must call the security module and get its security group IDs."
  }
}

run "dns_module_gives_the_zone_and_validated_certificates" {
  command = plan

  override_resource {
    target          = module.dns.aws_route53_zone.this
    override_during = plan
    values = {
      zone_id = "Z0TEST"
    }
  }

  assert {
    condition = (
      module.dns.zone_id == "Z0TEST" &&
      module.dns.cloudfront_certificate_arn == "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test" &&
      module.dns.alb_certificate_arn == "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
    )
    error_message = "The root must call the dns module and get its zone ID and certificate ARNs."
  }
}

run "database_module_gives_its_connection_details_and_secret" {
  command = plan

  # Fixed fake values for what RDS only knows once the database exists.
  override_resource {
    target          = module.database.aws_db_instance.this
    override_during = plan
    values = {
      address = "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com"
      master_user_secret = [
        {
          kms_key_id    = "arn:aws:kms:ap-southeast-3:111122223333:key/test"
          secret_arn    = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
          secret_status = "active"
        },
      ]
    }
  }

  assert {
    condition = (
      module.database.db_address == "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com" &&
      module.database.db_port == 3306 &&
      module.database.db_name == "wordpress" &&
      module.database.db_secret_arn == "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
    )
    error_message = "The root must call the database module and get its connection details and secret ARN."
  }

  # The committed values are for production, so the database is protected.
  assert {
    condition     = var.db_deletion_protection == true && var.db_skip_final_snapshot == false
    error_message = "terraform.tfvars must keep deletion protection and the final snapshot on."
  }
}

run "alb_module_gives_its_target_group_and_origin_name" {
  command = plan

  # Fixed fake values for what AWS only knows once the ALB exists. The ALB
  # gets a valid ARN too: an override fills every value it leaves out with a
  # random string, and the provider checks that the listener gets a real ARN.
  override_resource {
    target          = module.alb.aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0"
      dns_name = "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com"
      zone_id  = "Z0ALBZONE"
    }
  }

  override_resource {
    target          = module.alb.aws_lb_target_group.app
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"
    }
  }

  override_resource {
    target          = module.alb.aws_route53_record.origin
    override_during = plan
    values = {
      fqdn = "origin.webschool.example"
    }
  }

  assert {
    condition = (
      module.alb.target_group_arn == "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0" &&
      module.alb.alb_dns_name == "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com" &&
      module.alb.origin_fqdn == "origin.webschool.example"
    )
    error_message = "The root must call the alb module and get its target group, DNS name and origin name."
  }

  # CloudFront and the ALB share this secret. Letters and digits only,
  # because the ALB treats * and ? in header values as wildcards.
  assert {
    condition     = random_password.origin_verify.length == 32 && random_password.origin_verify.special == false
    error_message = "The origin secret must be 32 characters with no special characters."
  }

  assert {
    condition     = var.alb_deletion_protection == true
    error_message = "terraform.tfvars must keep the ALB's deletion protection on."
  }
}

run "compute_module_gives_its_group_and_role" {
  command = plan

  # A fixed fake ARN for what IAM only knows once the role exists.
  override_resource {
    target          = module.compute.aws_iam_role.instance
    override_during = plan
    values = {
      arn  = "arn:aws:iam::111122223333:role/web-school-prod-app-test"
      name = "web-school-prod-app-test"
    }
  }

  assert {
    condition = (
      module.compute.asg_name == "web-school-prod-app-asg" &&
      module.compute.instance_role_arn == "arn:aws:iam::111122223333:role/web-school-prod-app-test"
    )
    error_message = "The root must call the compute module and get its group name and role ARN."
  }
}

run "cdn_module_gives_its_distribution" {
  command = plan

  # Fixed fake values for what CloudFront only knows once the distribution
  # exists.
  override_resource {
    target          = module.cdn.aws_cloudfront_distribution.this
    override_during = plan
    values = {
      id          = "EDFDVBD6EXAMPLE"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }

  assert {
    condition = (
      module.cdn.distribution_id == "EDFDVBD6EXAMPLE" &&
      module.cdn.cloudfront_domain_name == "d111111abcdef8.cloudfront.net"
    )
    error_message = "The root must call the cdn module and get its distribution ID and domain name."
  }
}

run "outputs_show_the_site_and_where_its_parts_are" {
  command = plan

  # Fixed fake values for what AWS only knows once each resource exists. The
  # ALB gets a valid ARN too, because the provider checks the listener's.
  override_resource {
    target          = module.dns.aws_route53_zone.this
    override_during = plan
    values = {
      zone_id      = "Z0TEST"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"]
    }
  }

  override_resource {
    target          = module.alb.aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0"
      dns_name = "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com"
      zone_id  = "Z0ALBZONE"
    }
  }

  override_resource {
    target          = module.database.aws_db_instance.this
    override_during = plan
    values = {
      address = "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com"
      master_user_secret = [
        {
          kms_key_id    = "arn:aws:kms:ap-southeast-3:111122223333:key/test"
          secret_arn    = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
          secret_status = "active"
        },
      ]
    }
  }

  override_resource {
    target          = module.cdn.aws_cloudfront_distribution.this
    override_during = plan
    values = {
      id          = "EDFDVBD6EXAMPLE"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }

  assert {
    condition     = output.website_url == "https://webschool.example"
    error_message = "website_url must be the site's HTTPS address on the apex."
  }

  assert {
    condition     = output.name_servers == tolist(["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"])
    error_message = "name_servers must be the hosted zone's name servers, which the registrar must list."
  }

  assert {
    condition     = output.cloudfront_domain_name == "d111111abcdef8.cloudfront.net"
    error_message = "cloudfront_domain_name must be the distribution's domain name."
  }

  assert {
    condition     = output.cloudfront_distribution_id == "EDFDVBD6EXAMPLE"
    error_message = "cloudfront_distribution_id must be the distribution's ID, for cache invalidations."
  }

  assert {
    condition     = output.alb_dns_name == "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com"
    error_message = "alb_dns_name must be the ALB's own DNS name."
  }

  assert {
    condition     = output.asg_name == "web-school-prod-app-asg"
    error_message = "asg_name must be the Auto Scaling group's name."
  }

  # Host and port, as WordPress's WORDPRESS_DB_HOST takes them.
  assert {
    condition     = output.db_endpoint == "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com:3306"
    error_message = "db_endpoint must be the database's host name and port."
  }

  assert {
    condition     = output.db_secret_arn == "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
    error_message = "db_secret_arn must be the ARN of the secret that RDS manages."
  }
}
