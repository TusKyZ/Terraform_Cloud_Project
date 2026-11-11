# Unit tests for modules/security. They plan against a mock AWS provider, so
# they need no AWS credentials and create nothing.

mock_provider "aws" {}

variables {
  name_prefix         = "web-school-prod"
  vpc_id              = "vpc-0test"
  public_subnet_ids   = ["subnet-0public-a", "subnet-0public-b"]
  app_subnet_ids      = ["subnet-0app-a", "subnet-0app-b"]
  db_subnet_ids       = ["subnet-0db-a", "subnet-0db-b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
  db_subnet_cidrs     = ["10.0.21.0/24", "10.0.22.0/24"]
}

run "security_groups_are_in_the_vpc_and_named" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = (
      aws_security_group.alb.vpc_id == "vpc-0test" &&
      aws_security_group.app.vpc_id == "vpc-0test" &&
      aws_security_group.db.vpc_id == "vpc-0test"
    )
    error_message = "Every security group must be in the VPC."
  }

  # A name prefix, not a fixed name, so a replacement group can be created
  # while the old one still exists.
  assert {
    condition = (
      aws_security_group.alb.name_prefix == "web-school-prod-alb-" &&
      aws_security_group.app.name_prefix == "web-school-prod-app-" &&
      aws_security_group.db.name_prefix == "web-school-prod-db-"
    )
    error_message = "Security group name prefixes must be <name_prefix>-alb-, <name_prefix>-app- and <name_prefix>-db-."
  }

  assert {
    condition = (
      aws_security_group.alb.tags["Name"] == "web-school-prod-alb-sg" &&
      aws_security_group.app.tags["Name"] == "web-school-prod-app-sg" &&
      aws_security_group.db.tags["Name"] == "web-school-prod-db-sg"
    )
    error_message = "Security group Name tags must be <name_prefix>-alb-sg, <name_prefix>-app-sg and <name_prefix>-db-sg."
  }
}

run "security_group_rules_match_the_traffic_table" {
  command = plan

  module {
    source = "./modules/security"
  }

  # Fixed fake IDs, so each rule's group, source and destination can be
  # checked.
  override_data {
    target          = data.aws_ec2_managed_prefix_list.cloudfront
    override_during = plan
    values = {
      id = "pl-0cloudfront"
    }
  }

  override_resource {
    target          = aws_security_group.alb
    override_during = plan
    values = {
      id = "sg-0alb"
    }
  }

  override_resource {
    target          = aws_security_group.app
    override_during = plan
    values = {
      id = "sg-0app"
    }
  }

  override_resource {
    target          = aws_security_group.db
    override_during = plan
    values = {
      id = "sg-0db"
    }
  }

  assert {
    condition     = data.aws_ec2_managed_prefix_list.cloudfront.name == "com.amazonaws.global.cloudfront.origin-facing"
    error_message = "The ALB rule must use CloudFront's origin-facing prefix list."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.security_group_id == "sg-0alb" &&
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.ip_protocol == "tcp" &&
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.from_port == 443 &&
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.to_port == 443 &&
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.prefix_list_id == "pl-0cloudfront" &&
      aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.cidr_ipv4 == null
    )
    error_message = "ALB in: TCP 443 from CloudFront's prefix list only."
  }

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.alb_http_to_app.security_group_id == "sg-0alb" &&
      aws_vpc_security_group_egress_rule.alb_http_to_app.ip_protocol == "tcp" &&
      aws_vpc_security_group_egress_rule.alb_http_to_app.from_port == 80 &&
      aws_vpc_security_group_egress_rule.alb_http_to_app.to_port == 80 &&
      aws_vpc_security_group_egress_rule.alb_http_to_app.referenced_security_group_id == "sg-0app"
    )
    error_message = "ALB out: TCP 80 to the app security group only."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.app_http_from_alb.security_group_id == "sg-0app" &&
      aws_vpc_security_group_ingress_rule.app_http_from_alb.ip_protocol == "tcp" &&
      aws_vpc_security_group_ingress_rule.app_http_from_alb.from_port == 80 &&
      aws_vpc_security_group_ingress_rule.app_http_from_alb.to_port == 80 &&
      aws_vpc_security_group_ingress_rule.app_http_from_alb.referenced_security_group_id == "sg-0alb"
    )
    error_message = "App in: TCP 80 from the ALB security group only."
  }

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.app_mysql_to_db.security_group_id == "sg-0app" &&
      aws_vpc_security_group_egress_rule.app_mysql_to_db.ip_protocol == "tcp" &&
      aws_vpc_security_group_egress_rule.app_mysql_to_db.from_port == 3306 &&
      aws_vpc_security_group_egress_rule.app_mysql_to_db.to_port == 3306 &&
      aws_vpc_security_group_egress_rule.app_mysql_to_db.referenced_security_group_id == "sg-0db"
    )
    error_message = "App out: TCP 3306 to the DB security group."
  }

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.app_https_to_internet.security_group_id == "sg-0app" &&
      aws_vpc_security_group_egress_rule.app_https_to_internet.ip_protocol == "tcp" &&
      aws_vpc_security_group_egress_rule.app_https_to_internet.from_port == 443 &&
      aws_vpc_security_group_egress_rule.app_https_to_internet.to_port == 443 &&
      aws_vpc_security_group_egress_rule.app_https_to_internet.cidr_ipv4 == "0.0.0.0/0"
    )
    error_message = "App out: TCP 443 to the internet."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.db_mysql_from_app.security_group_id == "sg-0db" &&
      aws_vpc_security_group_ingress_rule.db_mysql_from_app.ip_protocol == "tcp" &&
      aws_vpc_security_group_ingress_rule.db_mysql_from_app.from_port == 3306 &&
      aws_vpc_security_group_ingress_rule.db_mysql_from_app.to_port == 3306 &&
      aws_vpc_security_group_ingress_rule.db_mysql_from_app.referenced_security_group_id == "sg-0app"
    )
    error_message = "DB in: TCP 3306 from the app security group only."
  }
}

# AWS accepts only these characters in security group and rule
# descriptions, and rejects anything else when the group or rule is created.
run "descriptions_use_only_characters_aws_allows" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = alltrue([
      for description in [
        aws_security_group.alb.description,
        aws_security_group.app.description,
        aws_security_group.db.description,
        aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront.description,
        aws_vpc_security_group_egress_rule.alb_http_to_app.description,
        aws_vpc_security_group_ingress_rule.app_http_from_alb.description,
        aws_vpc_security_group_egress_rule.app_mysql_to_db.description,
        aws_vpc_security_group_egress_rule.app_https_to_internet.description,
        aws_vpc_security_group_ingress_rule.db_mysql_from_app.description,
      ] :
      length(description) <= 255 && can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]+$", description))
    ])
    error_message = "Descriptions may use only a-z, A-Z, 0-9, spaces and ._-:/()#,@[]+=&;{}!$*, up to 255 characters."
  }
}

run "network_acls_are_in_the_vpc_named_and_on_their_tier_subnets" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = (
      aws_network_acl.public.vpc_id == "vpc-0test" &&
      aws_network_acl.app.vpc_id == "vpc-0test" &&
      aws_network_acl.db.vpc_id == "vpc-0test"
    )
    error_message = "Every network ACL must be in the VPC."
  }

  assert {
    condition = (
      aws_network_acl.public.subnet_ids == toset(["subnet-0public-a", "subnet-0public-b"]) &&
      aws_network_acl.app.subnet_ids == toset(["subnet-0app-a", "subnet-0app-b"]) &&
      aws_network_acl.db.subnet_ids == toset(["subnet-0db-a", "subnet-0db-b"])
    )
    error_message = "Each network ACL must cover exactly the subnets of its own tier."
  }

  assert {
    condition = (
      aws_network_acl.public.tags["Name"] == "web-school-prod-public-nacl" &&
      aws_network_acl.app.tags["Name"] == "web-school-prod-app-nacl" &&
      aws_network_acl.db.tags["Name"] == "web-school-prod-db-nacl"
    )
    error_message = "Network ACL Name tags must be <name_prefix>-public-nacl, <name_prefix>-app-nacl and <name_prefix>-db-nacl."
  }
}

# The network ACL tests write each rule as "<rule number> <action>
# <protocol> <CIDR block> <from port>-<to port>" and compare the complete set
# for one direction, so a missing or an extra rule fails the test.

run "public_network_acl_allows_only_its_flows" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.public.ingress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 0.0.0.0/0 443-443",
      "200 allow tcp 0.0.0.0/0 1024-65535",
    ])
    error_message = "Public in: only HTTPS from anywhere, and replies on 1024-65535."
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.public.egress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 10.0.11.0/24 80-80",
      "101 allow tcp 10.0.12.0/24 80-80",
      "200 allow tcp 0.0.0.0/0 443-443",
      "300 allow tcp 0.0.0.0/0 1024-65535",
    ])
    error_message = "Public out: only HTTP to the app subnets, HTTPS to anywhere, and replies on 1024-65535."
  }
}

run "app_network_acl_allows_only_its_flows" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.app.ingress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 10.0.1.0/24 80-80",
      "101 allow tcp 10.0.2.0/24 80-80",
      "200 allow tcp 0.0.0.0/0 1024-65535",
    ])
    error_message = "App in: only HTTP from the public subnets, and replies on 1024-65535."
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.app.egress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 10.0.21.0/24 3306-3306",
      "101 allow tcp 10.0.22.0/24 3306-3306",
      "200 allow tcp 0.0.0.0/0 443-443",
      "300 allow tcp 10.0.1.0/24 1024-65535",
      "301 allow tcp 10.0.2.0/24 1024-65535",
    ])
    error_message = "App out: only MySQL to the DB subnets, HTTPS to anywhere, and replies on 1024-65535 to the public subnets."
  }
}

run "db_network_acl_allows_only_its_flows" {
  command = plan

  module {
    source = "./modules/security"
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.db.ingress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 10.0.11.0/24 3306-3306",
      "101 allow tcp 10.0.12.0/24 3306-3306",
    ])
    error_message = "DB in: only MySQL from the app subnets."
  }

  assert {
    condition = toset([
      for rule in aws_network_acl.db.egress :
      "${rule.rule_no} ${rule.action} ${rule.protocol} ${rule.cidr_block} ${rule.from_port}-${rule.to_port}"
      ]) == toset([
      "100 allow tcp 10.0.11.0/24 1024-65535",
      "101 allow tcp 10.0.12.0/24 1024-65535",
    ])
    error_message = "DB out: only replies on 1024-65535 to the app subnets."
  }
}

run "outputs_are_the_security_group_ids" {
  command = plan

  module {
    source = "./modules/security"
  }

  override_resource {
    target          = aws_security_group.alb
    override_during = plan
    values = {
      id = "sg-0alb"
    }
  }

  override_resource {
    target          = aws_security_group.app
    override_during = plan
    values = {
      id = "sg-0app"
    }
  }

  override_resource {
    target          = aws_security_group.db
    override_during = plan
    values = {
      id = "sg-0db"
    }
  }

  assert {
    condition = (
      output.alb_sg_id == "sg-0alb" &&
      output.app_sg_id == "sg-0app" &&
      output.db_sg_id == "sg-0db"
    )
    error_message = "Each output must be the ID of its own security group."
  }
}

run "invalid_subnet_cidrs_are_rejected" {
  command = plan

  module {
    source = "./modules/security"
  }

  variables {
    public_subnet_cidrs = ["10.0.1.0/24", "2001:db8::/64"]
    app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/33"]
    db_subnet_cidrs     = ["not-a-cidr"]
  }

  expect_failures = [var.public_subnet_cidrs, var.app_subnet_cidrs, var.db_subnet_cidrs]
}

# With no CIDR blocks, the per-subnet rules would silently disappear.
run "empty_subnet_cidrs_are_rejected" {
  command = plan

  module {
    source = "./modules/security"
  }

  variables {
    public_subnet_cidrs = []
    app_subnet_cidrs    = []
    db_subnet_cidrs     = []
  }

  expect_failures = [var.public_subnet_cidrs, var.app_subnet_cidrs, var.db_subnet_cidrs]
}
