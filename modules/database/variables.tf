variable "db_sg_id" {
  type        = string
  description = "ID of the DB security group, which allows MySQL only from the app instances."
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "IDs of the DB subnets, one per AZ. RDS needs subnets in at least two AZs."

  validation {
    condition     = length(var.db_subnet_ids) >= 2
    error_message = "db_subnet_ids must list at least two subnets, one per AZ: an RDS subnet group must cover at least two AZs."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Whether RDS refuses to delete the database. Set to false only for a throwaway deploy."
  default     = true
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, such as web-school-prod."
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Whether deleting the database skips the final snapshot. Set to true only for a throwaway deploy."
  default     = false
}
