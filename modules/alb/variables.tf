variable "alb_certificate_arn" {
  type        = string
  description = "ARN of the validated ACM certificate for the origin name, for the HTTPS listener."
}

variable "alb_sg_id" {
  type        = string
  description = "ID of the ALB security group, which allows HTTPS only from CloudFront."
}

variable "deletion_protection" {
  type        = bool
  description = "Whether AWS refuses to delete the ALB. Set to false only for a throwaway deploy."
  default     = true
}

variable "domain_name" {
  type        = string
  description = "Domain name of the site, such as webschool.example. The module points the origin name, origin.webschool.example in that case, at the ALB."

  # The dns module's rule, so this module also refuses a bad name when used
  # on its own: the name becomes the origin record.
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name such as webschool.example, without a scheme, wildcard or trailing dot."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "origin_verify_secret" {
  type        = string
  description = "Secret that CloudFront sends in the X-Origin-Verify header. The ALB forwards only requests that carry it."
  sensitive   = true

  # The ALB compares header values without regard to case and treats * and ?
  # as wildcards, so the secret is long and has letters and digits only.
  validation {
    condition     = can(regex("^[A-Za-z0-9]{32,}$", var.origin_verify_secret))
    error_message = "origin_verify_secret must be at least 32 letters and digits, with no * or ?, which the ALB would treat as wildcards."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs of the public subnets, one per AZ. An ALB needs subnets in at least two AZs."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "public_subnet_ids must list at least two subnets, one per AZ: an ALB needs subnets in at least two AZs."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC, for the target group."
}

variable "zone_id" {
  type        = string
  description = "ID of the public hosted zone that gets the origin record."
}
