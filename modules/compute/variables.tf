variable "ami_id" {
  type        = string
  description = "AMI for the instances. Leave null to use the latest Amazon Linux 2023 for x86_64, or set it to pin one AMI. It must be an Amazon Linux 2023 AMI: user_data uses dnf, and the launch template sets up its root device, /dev/xvda."
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-([0-9a-f]{8}|[0-9a-f]{17})$", var.ami_id))
    error_message = "ami_id must be null or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "app_sg_id" {
  type        = string
  description = "ID of the app security group, which allows HTTP only from the ALB."
}

variable "app_subnet_ids" {
  type        = list(string)
  description = "IDs of the app subnets, one per AZ. The Auto Scaling group spreads the instances over them."

  validation {
    condition     = length(var.app_subnet_ids) >= 2
    error_message = "app_subnet_ids must list at least two subnets, one per AZ, so the instances do not all sit in one AZ."
  }
}

variable "db_address" {
  type        = string
  description = "Host name of the database."
}

variable "db_name" {
  type        = string
  description = "Name of the WordPress database."
}

variable "db_port" {
  type        = number
  description = "Port the database listens on."
}

variable "db_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret where RDS keeps the master user's credentials. The instances read the database user name and password from it."
}

variable "domain_name" {
  type        = string
  description = "Domain name of the site, such as webschool.example. WordPress builds its links from https://webschool.example in that case."

  # The dns module's rule, so this module also refuses a bad name when used
  # on its own: the name goes into WordPress's PHP settings.
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name such as webschool.example, without a scheme, wildcard or trailing dot."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the WordPress instances."
  default     = "t3.small"
}

variable "max_size" {
  type        = number
  description = "Largest number of instances the Auto Scaling group may run."
  default     = 4

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
}

variable "min_size" {
  type        = number
  description = "Smallest number of instances the Auto Scaling group keeps running."
  default     = 1

  validation {
    condition     = var.min_size >= 0 && var.min_size <= var.max_size
    error_message = "min_size must be between 0 and max_size."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "scale_in_cpu_threshold" {
  type        = number
  description = "Average CPU percentage of the group below which, for 30 minutes, the group removes an instance."
  default     = 40

  # Below the scale-out threshold, or the group could add and remove
  # instances in turn.
  validation {
    condition     = var.scale_in_cpu_threshold >= 0 && var.scale_in_cpu_threshold < var.scale_out_cpu_threshold
    error_message = "scale_in_cpu_threshold must be at least 0 and below scale_out_cpu_threshold."
  }
}

variable "scale_out_cpu_threshold" {
  type        = number
  description = "Average CPU percentage of the group above which, for 30 minutes, the group adds an instance."
  default     = 80

  validation {
    condition     = var.scale_out_cpu_threshold >= 0 && var.scale_out_cpu_threshold <= 100
    error_message = "scale_out_cpu_threshold must be between 0 and 100."
  }
}

variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB's target group. The Auto Scaling group registers its instances in it."
}

variable "wordpress_image" {
  type        = string
  description = "The official WordPress image, Apache variant, with a full version tag, such as public.ecr.aws/docker/library/wordpress:7.1.3-php8.3-apache. A new tag makes a new launch template version, which the Auto Scaling group rolls out."

  # A tag such as 7.1.3-php8.3-apache fixes the WordPress, PHP and Apache
  # versions, so every instance runs the same code. The Apache variant is the
  # one that serves HTTP on port 80.
  validation {
    condition     = can(regex(":[0-9]+\\.[0-9]+\\.[0-9]+-php[0-9]+\\.[0-9]+-apache$", var.wordpress_image))
    error_message = "wordpress_image must end in a full version tag of the Apache variant, such as :7.1.3-php8.3-apache. Tags such as latest or 7.1-php8.3-apache move to new releases."
  }
}
