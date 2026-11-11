# Unit tests for modules/alb. They plan against a mock AWS provider, so they
# need no AWS credentials and create nothing.

mock_provider "aws" {}

variables {
  name_prefix          = "web-school-prod"
  vpc_id               = "vpc-0test"
  public_subnet_ids    = ["subnet-0public-a", "subnet-0public-b"]
  alb_sg_id            = "sg-0alb"
  alb_certificate_arn  = "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
  origin_verify_secret = "FakeTestSecret0123456789abcdefgh"
  zone_id              = "Z0TEST"
  domain_name          = "webschool.example"
}

run "alb_is_internet_facing_in_the_public_subnets" {
  command = plan

  module {
    source = "./modules/alb"
  }

  assert {
    condition = (
      aws_lb.this.load_balancer_type == "application" &&
      aws_lb.this.internal == false
    )
    error_message = "The load balancer must be an internet-facing Application Load Balancer."
  }

  assert {
    condition = (
      aws_lb.this.subnets == toset(["subnet-0public-a", "subnet-0public-b"]) &&
      aws_lb.this.security_groups == toset(["sg-0alb"])
    )
    error_message = "The ALB must sit in the public subnets behind the ALB security group only."
  }

  assert {
    condition = (
      aws_lb.this.name == "web-school-prod-alb" &&
      aws_lb.this.tags["Name"] == "web-school-prod-alb"
    )
    error_message = "The ALB's name and Name tag must be <name_prefix>-alb."
  }
}

run "alb_drops_invalid_headers_and_has_deletion_protection_by_default" {
  command = plan

  module {
    source = "./modules/alb"
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "The ALB must drop invalid header fields."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "Deletion protection must be on by default."
  }
}

run "throwaway_deploy_can_turn_off_deletion_protection" {
  command = plan

  module {
    source = "./modules/alb"
  }

  variables {
    deletion_protection = false
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == false
    error_message = "deletion_protection must reach the ALB."
  }
}

run "only_listener_is_https_443_with_a_default_403" {
  command = plan

  module {
    source = "./modules/alb"
  }

  # A fixed fake ARN, so the listener's load balancer can be checked.
  override_resource {
    target          = aws_lb.this
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0"
    }
  }

  assert {
    condition = (
      aws_lb_listener.https.load_balancer_arn == "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0" &&
      aws_lb_listener.https.port == 443 &&
      aws_lb_listener.https.protocol == "HTTPS"
    )
    error_message = "The ALB's listener must be HTTPS on port 443."
  }

  assert {
    condition = (
      aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09" &&
      aws_lb_listener.https.certificate_arn == "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
    )
    error_message = "The listener must use AWS's recommended TLS 1.3 and 1.2 policy and the ALB certificate."
  }

  # Anything that no rule forwards gets a 403 from the ALB itself.
  assert {
    condition = (
      length(aws_lb_listener.https.default_action) == 1 &&
      aws_lb_listener.https.default_action[0].type == "fixed-response" &&
      aws_lb_listener.https.default_action[0].fixed_response[0].status_code == "403"
    )
    error_message = "The listener's default action must be a fixed 403."
  }
}

run "target_group_is_http_80_with_a_health_check_on_the_home_page" {
  command = plan

  module {
    source = "./modules/alb"
  }

  assert {
    condition = (
      aws_lb_target_group.app.port == 80 &&
      aws_lb_target_group.app.protocol == "HTTP" &&
      aws_lb_target_group.app.target_type == "instance" &&
      aws_lb_target_group.app.vpc_id == "vpc-0test"
    )
    error_message = "The target group must send HTTP on port 80 to instances in the VPC."
  }

  # 200-399 also accepts the redirects WordPress sends from its home page.
  assert {
    condition = (
      aws_lb_target_group.app.health_check[0].path == "/" &&
      aws_lb_target_group.app.health_check[0].matcher == "200-399"
    )
    error_message = "The health check must request / and accept 200-399."
  }

  assert {
    condition     = aws_lb_target_group.app.deregistration_delay == "30"
    error_message = "Instances must drain for 30 seconds when they leave the target group."
  }

  # A name prefix, not a fixed name, so a replacement target group can be
  # created while the old one is still in use.
  assert {
    condition = (
      aws_lb_target_group.app.name_prefix == "app-" &&
      aws_lb_target_group.app.tags["Name"] == "web-school-prod-app-tg"
    )
    error_message = "The target group must use the name prefix app- and the Name tag <name_prefix>-app-tg."
  }
}

run "only_requests_with_the_origin_secret_reach_the_instances" {
  command = plan

  module {
    source = "./modules/alb"
  }

  # Fixed fake ARNs, so the rule's listener and target group can be checked.
  override_resource {
    target          = aws_lb_listener.https
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:listener/app/test/0/0"
    }
  }

  override_resource {
    target          = aws_lb_target_group.app
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"
    }
  }

  assert {
    condition     = aws_lb_listener_rule.origin_verify.listener_arn == "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:listener/app/test/0/0"
    error_message = "The rule must belong to the HTTPS listener."
  }

  # One condition: the X-Origin-Verify header must carry the secret.
  assert {
    condition = (
      length(aws_lb_listener_rule.origin_verify.condition) == 1 &&
      one(aws_lb_listener_rule.origin_verify.condition).http_header[0].http_header_name == "X-Origin-Verify" &&
      one(aws_lb_listener_rule.origin_verify.condition).http_header[0].values == toset(["FakeTestSecret0123456789abcdefgh"])
    )
    error_message = "The rule must match only the X-Origin-Verify header against the origin secret."
  }

  assert {
    condition = (
      length(aws_lb_listener_rule.origin_verify.action) == 1 &&
      aws_lb_listener_rule.origin_verify.action[0].type == "forward" &&
      aws_lb_listener_rule.origin_verify.action[0].target_group_arn == "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"
    )
    error_message = "The rule must forward matching requests to the target group."
  }
}

run "origin_name_points_at_the_alb" {
  command = plan

  module {
    source = "./modules/alb"
  }

  # Fixed fake values for the ALB's DNS name and hosted zone. The ARN is set
  # too: an override fills every value it leaves out with a random string,
  # and the provider still checks that the listener gets a valid ARN.
  override_resource {
    target          = aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0"
      dns_name = "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com"
      zone_id  = "Z0ALBZONE"
    }
  }

  assert {
    condition = (
      aws_route53_record.origin.zone_id == "Z0TEST" &&
      aws_route53_record.origin.name == "origin.webschool.example" &&
      aws_route53_record.origin.type == "A"
    )
    error_message = "The hosted zone must get an A record for origin.<domain_name>."
  }

  assert {
    condition = (
      length(aws_route53_record.origin.alias) == 1 &&
      aws_route53_record.origin.alias[0].name == "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com" &&
      aws_route53_record.origin.alias[0].zone_id == "Z0ALBZONE"
    )
    error_message = "The origin record must be an alias to the ALB."
  }
}

run "outputs_are_the_target_group_the_alb_and_the_origin_name" {
  command = plan

  module {
    source = "./modules/alb"
  }

  # Fixed fake values for what AWS only knows once the ALB exists.
  override_resource {
    target          = aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:loadbalancer/app/test/0"
      dns_name = "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com"
      zone_id  = "Z0ALBZONE"
    }
  }

  override_resource {
    target          = aws_lb_target_group.app
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"
    }
  }

  override_resource {
    target          = aws_route53_record.origin
    override_during = plan
    values = {
      fqdn = "origin.webschool.example"
    }
  }

  assert {
    condition = (
      output.target_group_arn == "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0" &&
      output.alb_dns_name == "web-school-prod-alb-123456789.ap-southeast-3.elb.amazonaws.com" &&
      output.origin_fqdn == "origin.webschool.example"
    )
    error_message = "The outputs must be the target group's ARN, the ALB's DNS name and the origin record's name."
  }
}

# An ALB needs subnets in at least two AZs.
run "single_public_subnet_is_rejected" {
  command = plan

  module {
    source = "./modules/alb"
  }

  variables {
    public_subnet_ids = ["subnet-0public-a"]
  }

  expect_failures = [var.public_subnet_ids]
}

# The ALB treats * and ? in header values as wildcards, so the secret must be
# letters and digits only.
run "origin_secret_with_wildcards_is_rejected" {
  command = plan

  module {
    source = "./modules/alb"
  }

  variables {
    origin_verify_secret = "FakeTestSecret0123456789abcdef*?"
  }

  expect_failures = [var.origin_verify_secret]
}

run "short_origin_secret_is_rejected" {
  command = plan

  module {
    source = "./modules/alb"
  }

  variables {
    origin_verify_secret = "FakeTestSecret"
  }

  expect_failures = [var.origin_verify_secret]
}

# The same rule as the dns module's, so the module refuses a bad name when
# used on its own too.
run "domain_name_with_a_scheme_is_rejected" {
  command = plan

  module {
    source = "./modules/alb"
  }

  variables {
    domain_name = "https://webschool.example"
  }

  expect_failures = [var.domain_name]
}
