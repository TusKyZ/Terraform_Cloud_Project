variable "domain_name" {
  type        = string
  description = "Domain name of the site, such as webschool.example. The module creates a public hosted zone for it."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name such as webschool.example, without a scheme, wildcard or trailing dot."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}
