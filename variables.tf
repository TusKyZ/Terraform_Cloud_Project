variable "alb_deletion_protection" {
  type        = bool
  description = "Whether AWS refuses to delete the ALB. Keep true; set to false only for a throwaway deploy."
}

variable "app_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the app subnets (WordPress instances), one per AZ in the same order as azs."
}

variable "aws_region" {
  type        = string
  description = "AWS Region for the stack. CloudFront and Route 53 are global, and the CloudFront certificate is in us-east-1."
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones to use, at least two, such as [\"ap-southeast-3a\", \"ap-southeast-3b\"]."
}

variable "db_deletion_protection" {
  type        = bool
  description = "Whether RDS refuses to delete the database. Keep true; set to false only for a throwaway deploy."
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "Whether deleting the database skips the final snapshot. Keep false; set to true only for a throwaway deploy."
}

variable "db_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the DB subnets (RDS), one per AZ in the same order as azs."
}

variable "domain_name" {
  type        = string
  description = "Domain name of the site, such as webschool.example. Terraform creates a public hosted zone for it, and the domain's registrar must point at that zone's name servers."
}

variable "environment" {
  type        = string
  description = "Environment name such as prod, used in resource names and the Environment tag."
}

variable "owner" {
  type        = string
  description = "Company or team that owns the stack, used in the Owner tag."
}

variable "project" {
  type        = string
  description = "Project name, used in resource names and the Project tag."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks for the public subnets (ALB and NAT gateways), one per AZ in the same order as azs."
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the VPC, such as 10.0.0.0/16."
}

variable "wordpress_image" {
  type        = string
  description = "The official WordPress image, Apache variant, with a full version tag such as 7.1.3-php8.3-apache, never latest. Change the tag to roll out a new WordPress version."
}
