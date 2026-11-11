resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # DNS on, as in a default VPC, so instances can resolve AWS names such as
  # the RDS endpoint.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# The public subnets' way to and from the internet: the ALB receives traffic
# through it and the NAT gateways send traffic out through it.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Every VPC comes with a default security group that lets its members reach
# each other and lets all traffic out. Nothing here uses it, so Terraform
# takes it over and removes its rules: anything launched without a security
# group gets no access.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # Empty lists, not omitted blocks: only then does Terraform also remove
  # rules someone adds later by hand.
  ingress = []
  egress  = []

  tags = {
    Name = "${var.name_prefix}-default-locked"
  }
}

# Every VPC also comes with a default network ACL that allows all traffic.
# The security module gives every subnet its own network ACL, so nothing
# uses this one. Terraform takes it over and removes its rules, so a subnet
# that ends up on it gets no traffic at all. Unlike the default security
# group, no empty lists are needed: ingress and egress here are plain
# blocks, so leaving them out means no rules.
resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  tags = {
    Name = "${var.name_prefix}-default-nacl-locked"
  }

  # AWS moves a subnet onto the default network ACL whenever it leaves
  # another one, so AWS, not Terraform, decides which subnets are on it.
  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

# Subnets are keyed by AZ name, not by list position, so removing or
# reordering an AZ never renumbers and recreates the other subnets.

# Public subnets hold the ALB and the NAT gateways. Neither needs instances
# to get a public IP at launch, so that stays off.
resource "aws_subnet" "public" {
  for_each = zipmap(var.azs, var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
  }
}

# App subnets hold the WordPress instances. Their only way out to the
# internet is the NAT gateway in their own AZ.
resource "aws_subnet" "app" {
  for_each = zipmap(var.azs, var.app_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.name_prefix}-app-${each.key}"
  }
}

# DB subnets hold RDS. They get no route to the internet.
resource "aws_subnet" "db" {
  for_each = zipmap(var.azs, var.db_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.name_prefix}-db-${each.key}"
  }
}

# One NAT gateway per AZ, each in that AZ's public subnet with its own
# Elastic IP. If one AZ fails, the app subnets in the other AZ keep their way
# out to the internet.
resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "this" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = {
    Name = "${var.name_prefix}-nat-${each.key}"
  }

  # The provider docs recommend this. AWS refuses to create a public NAT
  # gateway in a VPC with no internet gateway attached, and refuses to detach
  # the internet gateway while public IPs are still in use.
  depends_on = [aws_internet_gateway.this]
}

# Route tables list their routes inline, so Terraform owns the routes in
# them: a route added outside Terraform shows up in the next plan, and apply
# removes it. Every table also has an implicit local route for the VPC CIDR.

# The public subnets share one route table: the internet gateway serves the
# whole VPC, not one AZ.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One app route table per AZ, because a table can hold only one 0.0.0.0/0
# route and each AZ must leave through its own NAT gateway.
resource "aws_route_table" "app" {
  for_each = aws_nat_gateway.this

  vpc_id = aws_vpc.this.id

  # nat_gateway_id, not gateway_id: AWS accepts a NAT gateway ID in either,
  # but in gateway_id it causes a permanent diff in every plan.
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = each.value.id
  }

  tags = {
    Name = "${var.name_prefix}-app-rt-${each.key}"
  }
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# The DB subnets share one route table with no routes, so RDS has no way to
# or from the internet.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  # An empty list, not an omitted argument: only then does Terraform also
  # remove routes someone adds later by hand.
  route = []

  tags = {
    Name = "${var.name_prefix}-db-rt"
  }
}

resource "aws_route_table_association" "db" {
  for_each = aws_subnet.db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.db.id
}
