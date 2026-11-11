# CloudFront's origin-facing IP ranges, as a prefix list that AWS keeps up
# to date. It counts as 55 rules toward a security group's quota of 60.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Security groups are stateful: the reply to an allowed connection is let
# back in automatically, so only the side that opens a connection needs a
# rule. Terraform removes the allow-all egress rule that AWS adds to every new
# group, so each group allows only the rules below.
#
# AWS cannot delete a group that is still attached to something, and a new
# description forces a new group. create_before_destroy builds the new group
# first, and name_prefix gives it a name that does not clash with the old one.

resource "aws_security_group" "alb" {
  # checkov:skip=CKV2_AWS_5:False positive. The ALB in the alb module uses this group, and this graph check cannot follow module outputs. The tests check the attachment.
  name_prefix = "${var.name_prefix}-alb-"
  description = "ALB: HTTPS from CloudFront, HTTP to the app instances"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  # checkov:skip=CKV2_AWS_5:False positive. The launch template in the compute module uses this group, and this graph check cannot follow module outputs. The tests check the attachment.
  name_prefix = "${var.name_prefix}-app-"
  description = "App instances: HTTP from the ALB, MySQL to RDS, HTTPS out"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "db" {
  # checkov:skip=CKV2_AWS_5:False positive. The database in the database module uses this group, and this graph check cannot follow module outputs. The tests check the attachment.
  name_prefix = "${var.name_prefix}-db-"
  description = "RDS: MySQL from the app instances only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Only CloudFront can reach the ALB. Any CloudFront distribution could, so
# the ALB listener also checks a secret header that only ours sends.
resource "aws_vpc_security_group_ingress_rule" "alb_https_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from CloudFront origin-facing servers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_http_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP to the app instances"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  # checkov:skip=CKV_AWS_260:False positive. The source is the ALB security group, and the check does not read referenced_security_group_id.
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_mysql_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "MySQL to RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.db.id
}

# Through the NAT gateways: Secrets Manager, Session Manager, the WordPress
# image download and package updates all use HTTPS.
resource "aws_vpc_security_group_egress_rule" "app_https_to_internet" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out through the NAT gateways"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# The DB group has no egress rules: RDS only answers connections, and those
# replies need no rule.
resource "aws_vpc_security_group_ingress_rule" "db_mysql_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from the app instances"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}

# Network ACLs are stateless: a reply is checked like any other packet, so
# every flow needs a rule in each direction. A reply goes to the port the
# other side picked, anywhere in 1024-65535 (NAT gateways use that whole
# range), so the reply rules cover all of it.
#
# Rules are inline, so Terraform owns them: a rule added outside Terraform
# shows up in the next plan, and apply removes it. A rule that covers a tier
# gets one entry per subnet CIDR block, numbered up from its group's base
# number (100, 200 or 300).

resource "aws_network_acl" "public" {
  # checkov:skip=CKV2_AWS_1:False positive. subnet_ids comes from the network module, and this graph check cannot follow module outputs. The tests check the attachment.
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # HTTPS in: CloudFront to the ALB, and app instances to the NAT gateways.
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Replies in: from the app instances to the ALB, and from the internet to
  # the NAT gateways.
  ingress {
    rule_no    = 200
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # HTTP out from the ALB to the app instances.
  dynamic "egress" {
    for_each = var.app_subnet_cidrs

    content {
      rule_no    = 100 + egress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = egress.value
      from_port  = 80
      to_port    = 80
    }
  }

  # HTTPS out from the NAT gateways to the internet.
  egress {
    rule_no    = 200
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Replies out: from the ALB to CloudFront, and from the NAT gateways to the
  # app instances.
  egress {
    rule_no    = 300
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.name_prefix}-public-nacl"
  }
}

resource "aws_network_acl" "app" {
  # checkov:skip=CKV2_AWS_1:False positive. subnet_ids comes from the network module, and this graph check cannot follow module outputs. The tests check the attachment.
  vpc_id     = var.vpc_id
  subnet_ids = var.app_subnet_ids

  # HTTP in from the ALB.
  dynamic "ingress" {
    for_each = var.public_subnet_cidrs

    content {
      rule_no    = 100 + ingress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = ingress.value
      from_port  = 80
      to_port    = 80
    }
  }

  # Replies in: from RDS, and from the internet through the NAT gateways.
  ingress {
    rule_no    = 200
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # MySQL out to RDS.
  dynamic "egress" {
    for_each = var.db_subnet_cidrs

    content {
      rule_no    = 100 + egress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = egress.value
      from_port  = 3306
      to_port    = 3306
    }
  }

  # HTTPS out to the internet, through the NAT gateways.
  egress {
    rule_no    = 200
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Replies out to the ALB.
  dynamic "egress" {
    for_each = var.public_subnet_cidrs

    content {
      rule_no    = 300 + egress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  tags = {
    Name = "${var.name_prefix}-app-nacl"
  }
}

resource "aws_network_acl" "db" {
  # checkov:skip=CKV2_AWS_1:False positive. subnet_ids comes from the network module, and this graph check cannot follow module outputs. The tests check the attachment.
  vpc_id     = var.vpc_id
  subnet_ids = var.db_subnet_ids

  # MySQL in from the app instances.
  dynamic "ingress" {
    for_each = var.app_subnet_cidrs

    content {
      rule_no    = 100 + ingress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = ingress.value
      from_port  = 3306
      to_port    = 3306
    }
  }

  # Replies out to the app instances only. RDS opens no connections of its
  # own, and the DB subnets have no route to the internet.
  dynamic "egress" {
    for_each = var.app_subnet_cidrs

    content {
      rule_no    = 100 + egress.key
      action     = "allow"
      protocol   = "tcp"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  tags = {
    Name = "${var.name_prefix}-db-nacl"
  }
}
