variable "cloudfront_certificate_arn" {
  type        = string
  description = "ARN of the validated ACM certificate for the apex and www. CloudFront accepts only certificates from us-east-1."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:us-east-1:", var.cloudfront_certificate_arn))
    error_message = "cloudfront_certificate_arn must be an ACM certificate in us-east-1, the only Region CloudFront takes certificates from."
  }
}

variable "domain_name" {
  type        = string
  description = "Domain name of the site, such as webschool.example. CloudFront serves it and its www name."

  # The dns module's rule, so this module also refuses a bad name when used
  # on its own: the name goes into the CloudFront Function's code.
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name such as webschool.example, without a scheme, wildcard or trailing dot."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "origin_fqdn" {
  type        = string
  description = "Origin name that CloudFront connects to, such as origin.webschool.example. The ALB's certificate covers it."
}

variable "origin_verify_secret" {
  type        = string
  description = "Secret that CloudFront sends to the ALB in the X-Origin-Verify header. The ALB forwards only requests that carry it."
  sensitive   = true

  # The ALB compares header values without regard to case and treats * and ?
  # as wildcards, so the secret is long and has letters and digits only.
  validation {
    condition     = can(regex("^[A-Za-z0-9]{32,}$", var.origin_verify_secret))
    error_message = "origin_verify_secret must be at least 32 letters and digits, with no * or ?, which the ALB would treat as wildcards."
  }
}

variable "zone_id" {
  type        = string
  description = "ID of the public hosted zone that gets the apex and www records."
}
