# The subnet lists follow the order of var.azs, not the sort order of the
# AZ names, so item N of every list is in the same AZ.

output "app_subnet_cidrs" {
  description = "IPv4 CIDR blocks of the app subnets, in the same order as azs."
  value       = [for az in var.azs : aws_subnet.app[az].cidr_block]
}

output "app_subnet_ids" {
  description = "IDs of the app subnets (WordPress instances), in the same order as azs."
  value       = [for az in var.azs : aws_subnet.app[az].id]
}

output "db_subnet_cidrs" {
  description = "IPv4 CIDR blocks of the DB subnets, in the same order as azs."
  value       = [for az in var.azs : aws_subnet.db[az].cidr_block]
}

output "db_subnet_ids" {
  description = "IDs of the DB subnets (RDS), in the same order as azs."
  value       = [for az in var.azs : aws_subnet.db[az].id]
}

output "public_subnet_cidrs" {
  description = "IPv4 CIDR blocks of the public subnets, in the same order as azs."
  value       = [for az in var.azs : aws_subnet.public[az].cidr_block]
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB and NAT gateways), in the same order as azs."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}
