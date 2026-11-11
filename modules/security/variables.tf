variable "app_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks of the app subnets, used in the network ACL rules."

  validation {
    condition     = length(var.app_subnet_cidrs) > 0 && alltrue([for cidr in var.app_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "app_subnet_cidrs must list at least one valid IPv4 CIDR block, such as 10.0.11.0/24."
  }
}

variable "app_subnet_ids" {
  type        = list(string)
  description = "IDs of the app subnets, which get the app network ACL."
}

variable "db_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks of the DB subnets, used in the network ACL rules."

  validation {
    condition     = length(var.db_subnet_cidrs) > 0 && alltrue([for cidr in var.db_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "db_subnet_cidrs must list at least one valid IPv4 CIDR block, such as 10.0.21.0/24."
  }
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "IDs of the DB subnets, which get the DB network ACL."
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks of the public subnets, used in the network ACL rules."

  validation {
    condition     = length(var.public_subnet_cidrs) > 0 && alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "public_subnet_cidrs must list at least one valid IPv4 CIDR block, such as 10.0.1.0/24."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs of the public subnets, which get the public network ACL."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC that the security groups and network ACLs belong to."
}
