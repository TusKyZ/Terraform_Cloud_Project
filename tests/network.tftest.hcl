# Unit tests for modules/network. They plan against a mock AWS provider, so
# they need no AWS credentials and create nothing.

mock_provider "aws" {}

variables {
  name_prefix         = "web-school-prod"
  vpc_cidr            = "10.0.0.0/16"
  azs                 = ["ap-southeast-3a", "ap-southeast-3b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
  db_subnet_cidrs     = ["10.0.21.0/24", "10.0.22.0/24"]
}

run "vpc_has_planned_cidr_dns_and_name" {
  command = plan

  module {
    source = "./modules/network"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "The VPC must use 10.0.0.0/16."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "The VPC must have DNS support and DNS hostnames turned on."
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "web-school-prod-vpc"
    error_message = "The VPC Name tag must be <name_prefix>-vpc."
  }
}

run "internet_gateway_is_attached_to_vpc" {
  command = plan

  module {
    source = "./modules/network"
  }

  # Real IDs are unknown at plan time, so give the VPC a fixed fake ID and
  # check that the gateway points at it.
  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id = "vpc-0test"
    }
  }

  assert {
    condition     = aws_internet_gateway.this.vpc_id == "vpc-0test"
    error_message = "The internet gateway must be attached to the VPC."
  }

  assert {
    condition     = aws_internet_gateway.this.tags["Name"] == "web-school-prod-igw"
    error_message = "The internet gateway Name tag must be <name_prefix>-igw."
  }
}

run "default_security_group_is_locked_down" {
  command = plan

  module {
    source = "./modules/network"
  }

  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id = "vpc-0test"
    }
  }

  assert {
    condition     = aws_default_security_group.this.vpc_id == "vpc-0test"
    error_message = "Terraform must manage the VPC's default security group."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "The default security group must have no rules."
  }

  assert {
    condition     = aws_default_security_group.this.tags["Name"] == "web-school-prod-default-locked"
    error_message = "The default security group Name tag must be <name_prefix>-default-locked."
  }
}

run "default_network_acl_is_locked_down" {
  command = plan

  module {
    source = "./modules/network"
  }

  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id                     = "vpc-0test"
      default_network_acl_id = "acl-0default"
    }
  }

  assert {
    condition     = aws_default_network_acl.this.default_network_acl_id == "acl-0default"
    error_message = "Terraform must manage the VPC's default network ACL."
  }

  # No rules at all, so the default network ACL denies all traffic.
  assert {
    condition     = length(aws_default_network_acl.this.ingress) == 0 && length(aws_default_network_acl.this.egress) == 0
    error_message = "The default network ACL must have no rules."
  }

  assert {
    condition     = aws_default_network_acl.this.tags["Name"] == "web-school-prod-default-nacl-locked"
    error_message = "The default network ACL Name tag must be <name_prefix>-default-nacl-locked."
  }
}

run "subnets_have_planned_cidrs_azs_and_names" {
  command = plan

  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.db) == 2
    error_message = "There must be one public, one app and one DB subnet in each of the two AZs."
  }

  assert {
    condition = (
      aws_subnet.public["ap-southeast-3a"].cidr_block == "10.0.1.0/24" &&
      aws_subnet.public["ap-southeast-3b"].cidr_block == "10.0.2.0/24"
    )
    error_message = "Public subnets must be 10.0.1.0/24 in AZ a and 10.0.2.0/24 in AZ b."
  }

  assert {
    condition = (
      aws_subnet.app["ap-southeast-3a"].cidr_block == "10.0.11.0/24" &&
      aws_subnet.app["ap-southeast-3b"].cidr_block == "10.0.12.0/24"
    )
    error_message = "App subnets must be 10.0.11.0/24 in AZ a and 10.0.12.0/24 in AZ b."
  }

  assert {
    condition = (
      aws_subnet.db["ap-southeast-3a"].cidr_block == "10.0.21.0/24" &&
      aws_subnet.db["ap-southeast-3b"].cidr_block == "10.0.22.0/24"
    )
    error_message = "DB subnets must be 10.0.21.0/24 in AZ a and 10.0.22.0/24 in AZ b."
  }

  assert {
    condition = alltrue([
      for az in ["ap-southeast-3a", "ap-southeast-3b"] :
      aws_subnet.public[az].availability_zone == az &&
      aws_subnet.app[az].availability_zone == az &&
      aws_subnet.db[az].availability_zone == az
    ])
    error_message = "Each subnet must be in the AZ it is keyed by."
  }

  assert {
    condition = alltrue([
      for az in ["ap-southeast-3a", "ap-southeast-3b"] :
      aws_subnet.public[az].tags["Name"] == "web-school-prod-public-${az}" &&
      aws_subnet.app[az].tags["Name"] == "web-school-prod-app-${az}" &&
      aws_subnet.db[az].tags["Name"] == "web-school-prod-db-${az}"
    ])
    error_message = "Subnet Name tags must be <name_prefix>-<tier>-<az>."
  }
}

run "subnets_are_in_the_vpc" {
  command = plan

  module {
    source = "./modules/network"
  }

  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id = "vpc-0test"
    }
  }

  assert {
    condition = alltrue([
      for subnet in concat(values(aws_subnet.public), values(aws_subnet.app), values(aws_subnet.db)) :
      subnet.vpc_id == "vpc-0test"
    ])
    error_message = "Every subnet must be in the VPC."
  }
}

run "subnets_do_not_assign_public_ips" {
  command = plan

  module {
    source = "./modules/network"
  }

  # Left unset, the setting is null at plan time and AWS treats it as off,
  # so the check is "not true" rather than "false".
  assert {
    condition = alltrue([
      for subnet in concat(values(aws_subnet.public), values(aws_subnet.app), values(aws_subnet.db)) :
      subnet.map_public_ip_on_launch != true
    ])
    error_message = "No subnet may give instances a public IP at launch."
  }
}

run "one_nat_gateway_and_elastic_ip_per_az" {
  command = plan

  module {
    source = "./modules/network"
  }

  assert {
    condition     = length(aws_eip.nat) == 2 && length(aws_nat_gateway.this) == 2
    error_message = "There must be one NAT gateway and one Elastic IP in each of the two AZs."
  }

  assert {
    condition     = alltrue([for eip in values(aws_eip.nat) : eip.domain == "vpc"])
    error_message = "The NAT gateways' Elastic IPs must be VPC Elastic IPs."
  }

  assert {
    condition = alltrue([
      for az in ["ap-southeast-3a", "ap-southeast-3b"] :
      aws_nat_gateway.this[az].tags["Name"] == "web-school-prod-nat-${az}" &&
      aws_eip.nat[az].tags["Name"] == "web-school-prod-nat-eip-${az}"
    ])
    error_message = "Name tags must be <name_prefix>-nat-<az> for NAT gateways and <name_prefix>-nat-eip-<az> for their Elastic IPs."
  }
}

run "nat_gateways_use_their_own_az" {
  command = plan

  module {
    source = "./modules/network"
  }

  # A different fake ID for each AZ's public subnet and Elastic IP, so a NAT
  # gateway wired to the other AZ would show up.
  override_resource {
    target          = aws_subnet.public["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "subnet-0public-a"
    }
  }

  override_resource {
    target          = aws_subnet.public["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "subnet-0public-b"
    }
  }

  override_resource {
    target          = aws_eip.nat["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "eipalloc-0a"
    }
  }

  override_resource {
    target          = aws_eip.nat["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "eipalloc-0b"
    }
  }

  assert {
    condition = (
      aws_nat_gateway.this["ap-southeast-3a"].subnet_id == "subnet-0public-a" &&
      aws_nat_gateway.this["ap-southeast-3b"].subnet_id == "subnet-0public-b"
    )
    error_message = "Each NAT gateway must be in the public subnet of its own AZ."
  }

  assert {
    condition = (
      aws_nat_gateway.this["ap-southeast-3a"].allocation_id == "eipalloc-0a" &&
      aws_nat_gateway.this["ap-southeast-3b"].allocation_id == "eipalloc-0b"
    )
    error_message = "Each NAT gateway must use the Elastic IP of its own AZ."
  }
}

run "public_route_table_sends_internet_traffic_to_the_internet_gateway" {
  command = plan

  module {
    source = "./modules/network"
  }

  override_resource {
    target          = aws_internet_gateway.this
    override_during = plan
    values = {
      id = "igw-0test"
    }
  }

  assert {
    condition = (
      length(aws_route_table.public.route) == 1 &&
      alltrue([
        for route in aws_route_table.public.route :
        route.cidr_block == "0.0.0.0/0" && route.gateway_id == "igw-0test"
      ])
    )
    error_message = "The public route table must have one route: 0.0.0.0/0 to the internet gateway."
  }
}

run "app_route_tables_use_the_nat_gateway_in_their_own_az" {
  command = plan

  module {
    source = "./modules/network"
  }

  # A different fake ID for each AZ's NAT gateway, so a route to the other
  # AZ's NAT gateway would show up.
  override_resource {
    target          = aws_nat_gateway.this["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "nat-0a"
    }
  }

  override_resource {
    target          = aws_nat_gateway.this["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "nat-0b"
    }
  }

  assert {
    condition     = length(aws_route_table.app) == 2
    error_message = "There must be one app route table in each of the two AZs."
  }

  assert {
    condition = alltrue([
      for az, nat_id in { "ap-southeast-3a" = "nat-0a", "ap-southeast-3b" = "nat-0b" } :
      length(aws_route_table.app[az].route) == 1 &&
      alltrue([
        for route in aws_route_table.app[az].route :
        route.cidr_block == "0.0.0.0/0" && route.nat_gateway_id == nat_id
      ])
    ])
    error_message = "Each app route table must have one route: 0.0.0.0/0 to the NAT gateway in its own AZ."
  }
}

run "db_route_table_has_no_routes" {
  command = plan

  module {
    source = "./modules/network"
  }

  # Only the implicit local route is left, so the DB subnets have no way to
  # the internet.
  assert {
    condition     = length(aws_route_table.db.route) == 0
    error_message = "The DB route table must have no routes besides the implicit local route."
  }
}

run "route_tables_are_in_the_vpc_and_named" {
  command = plan

  module {
    source = "./modules/network"
  }

  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id = "vpc-0test"
    }
  }

  assert {
    condition = (
      aws_route_table.public.vpc_id == "vpc-0test" &&
      aws_route_table.db.vpc_id == "vpc-0test" &&
      alltrue([for table in values(aws_route_table.app) : table.vpc_id == "vpc-0test"])
    )
    error_message = "Every route table must be in the VPC."
  }

  assert {
    condition = (
      aws_route_table.public.tags["Name"] == "web-school-prod-public-rt" &&
      aws_route_table.db.tags["Name"] == "web-school-prod-db-rt" &&
      alltrue([
        for az in ["ap-southeast-3a", "ap-southeast-3b"] :
        aws_route_table.app[az].tags["Name"] == "web-school-prod-app-rt-${az}"
      ])
    )
    error_message = "Route table Name tags must be <name_prefix>-public-rt, <name_prefix>-app-rt-<az> and <name_prefix>-db-rt."
  }
}

run "each_subnet_uses_its_tier_route_table" {
  command = plan

  module {
    source = "./modules/network"
  }

  # Public and DB subnets share one route table per tier, so one fake ID per
  # tier is enough there. App subnets and app route tables get one per AZ, so
  # an app subnet tied to the other AZ's route table would show up.
  override_resource {
    target          = aws_subnet.public
    override_during = plan
    values = {
      id = "subnet-0public"
    }
  }

  override_resource {
    target          = aws_subnet.db
    override_during = plan
    values = {
      id = "subnet-0db"
    }
  }

  override_resource {
    target          = aws_subnet.app["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "subnet-0app-a"
    }
  }

  override_resource {
    target          = aws_subnet.app["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "subnet-0app-b"
    }
  }

  override_resource {
    target          = aws_route_table.public
    override_during = plan
    values = {
      id = "rtb-0public"
    }
  }

  override_resource {
    target          = aws_route_table.db
    override_during = plan
    values = {
      id = "rtb-0db"
    }
  }

  override_resource {
    target          = aws_route_table.app["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "rtb-0app-a"
    }
  }

  override_resource {
    target          = aws_route_table.app["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "rtb-0app-b"
    }
  }

  assert {
    condition = alltrue([
      for az in ["ap-southeast-3a", "ap-southeast-3b"] :
      aws_route_table_association.public[az].subnet_id == "subnet-0public" &&
      aws_route_table_association.public[az].route_table_id == "rtb-0public"
    ])
    error_message = "Each public subnet must use the public route table."
  }

  assert {
    condition = (
      aws_route_table_association.app["ap-southeast-3a"].subnet_id == "subnet-0app-a" &&
      aws_route_table_association.app["ap-southeast-3a"].route_table_id == "rtb-0app-a" &&
      aws_route_table_association.app["ap-southeast-3b"].subnet_id == "subnet-0app-b" &&
      aws_route_table_association.app["ap-southeast-3b"].route_table_id == "rtb-0app-b"
    )
    error_message = "Each app subnet must use the app route table of its own AZ."
  }

  assert {
    condition = alltrue([
      for az in ["ap-southeast-3a", "ap-southeast-3b"] :
      aws_route_table_association.db[az].subnet_id == "subnet-0db" &&
      aws_route_table_association.db[az].route_table_id == "rtb-0db"
    ])
    error_message = "Each DB subnet must use the DB route table."
  }
}

run "outputs_list_each_tier_in_the_order_of_azs" {
  command = plan

  module {
    source = "./modules/network"
  }

  # The AZs are listed in reverse here, so outputs sorted by AZ name instead
  # of following azs would show up.
  variables {
    azs                 = ["ap-southeast-3b", "ap-southeast-3a"]
    public_subnet_cidrs = ["10.0.2.0/24", "10.0.1.0/24"]
    app_subnet_cidrs    = ["10.0.12.0/24", "10.0.11.0/24"]
    db_subnet_cidrs     = ["10.0.22.0/24", "10.0.21.0/24"]
  }

  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values = {
      id = "vpc-0test"
    }
  }

  override_resource {
    target          = aws_subnet.public["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "subnet-0public-a"
    }
  }

  override_resource {
    target          = aws_subnet.public["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "subnet-0public-b"
    }
  }

  override_resource {
    target          = aws_subnet.app["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "subnet-0app-a"
    }
  }

  override_resource {
    target          = aws_subnet.app["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "subnet-0app-b"
    }
  }

  override_resource {
    target          = aws_subnet.db["ap-southeast-3a"]
    override_during = plan
    values = {
      id = "subnet-0db-a"
    }
  }

  override_resource {
    target          = aws_subnet.db["ap-southeast-3b"]
    override_during = plan
    values = {
      id = "subnet-0db-b"
    }
  }

  assert {
    condition     = output.vpc_id == "vpc-0test"
    error_message = "vpc_id must be the ID of the VPC."
  }

  assert {
    condition = (
      output.public_subnet_ids == ["subnet-0public-b", "subnet-0public-a"] &&
      output.app_subnet_ids == ["subnet-0app-b", "subnet-0app-a"] &&
      output.db_subnet_ids == ["subnet-0db-b", "subnet-0db-a"]
    )
    error_message = "Each subnet ID output must list that tier's subnets in the order of azs."
  }

  assert {
    condition = (
      output.public_subnet_cidrs == ["10.0.2.0/24", "10.0.1.0/24"] &&
      output.app_subnet_cidrs == ["10.0.12.0/24", "10.0.11.0/24"] &&
      output.db_subnet_cidrs == ["10.0.22.0/24", "10.0.21.0/24"]
    )
    error_message = "Each subnet CIDR output must list that tier's CIDR blocks in the order of azs."
  }
}

run "invalid_vpc_cidr_is_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    vpc_cidr = "10.0.0.0/33"
  }

  expect_failures = [var.vpc_cidr]
}

run "ipv6_vpc_cidr_is_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    vpc_cidr = "2001:db8::/56"
  }

  expect_failures = [var.vpc_cidr]
}

run "single_az_is_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    azs                 = ["ap-southeast-3a"]
    public_subnet_cidrs = ["10.0.1.0/24"]
    app_subnet_cidrs    = ["10.0.11.0/24"]
    db_subnet_cidrs     = ["10.0.21.0/24"]
  }

  expect_failures = [var.azs]
}

run "duplicate_az_is_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    azs = ["ap-southeast-3a", "ap-southeast-3a"]
  }

  expect_failures = [var.azs]
}

# Each list breaks its own rule, so all three must fail.
run "subnet_cidrs_must_match_azs" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    public_subnet_cidrs = ["10.0.1.0/24"]
    app_subnet_cidrs    = ["10.0.11.0/24"]
    db_subnet_cidrs     = ["10.0.21.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs, var.app_subnet_cidrs, var.db_subnet_cidrs]
}

run "invalid_subnet_cidrs_are_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    public_subnet_cidrs = ["10.0.1.0/24", "2001:db8::/64"]
    app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/33"]
    db_subnet_cidrs     = ["10.0.21.0/24", "not-a-cidr"]
  }

  expect_failures = [var.public_subnet_cidrs, var.app_subnet_cidrs, var.db_subnet_cidrs]
}
