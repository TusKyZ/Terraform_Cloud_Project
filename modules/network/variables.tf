variable "app_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the app subnets (WordPress instances), one per AZ in the same order as azs."

  validation {
    condition     = length(var.app_subnet_cidrs) == length(var.azs)
    error_message = "app_subnet_cidrs must have one CIDR block per AZ in azs."
  }

  validation {
    condition     = alltrue([for cidr in var.app_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "app_subnet_cidrs must be valid IPv4 CIDR blocks, such as 10.0.11.0/24."
  }
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones to use, at least two, such as [\"ap-southeast-3a\", \"ap-southeast-3b\"]."

  validation {
    # The ALB and the RDS subnet group both need subnets in at least two AZs.
    # A repeated AZ would silently drop subnets, since they are keyed by AZ.
    condition     = length(var.azs) >= 2 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list at least two different Availability Zones, each once."
  }
}

variable "db_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the DB subnets (RDS), one per AZ in the same order as azs."

  validation {
    condition     = length(var.db_subnet_cidrs) == length(var.azs)
    error_message = "db_subnet_cidrs must have one CIDR block per AZ in azs."
  }

  validation {
    condition     = alltrue([for cidr in var.db_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "db_subnet_cidrs must be valid IPv4 CIDR blocks, such as 10.0.21.0/24."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the public subnets (ALB and NAT gateways), one per AZ in the same order as azs."

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have one CIDR block per AZ in azs."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "public_subnet_cidrs must be valid IPv4 CIDR blocks, such as 10.0.1.0/24."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the VPC, such as 10.0.0.0/16."

  validation {
    # cidrnetmask only accepts IPv4 CIDR blocks, so IPv6 is rejected too.
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, such as 10.0.0.0/16."
  }
}
