output "db_address" {
  description = "Host name of the database, for WordPress to connect to."
  value       = aws_db_instance.this.address
}

output "db_name" {
  description = "Name of the WordPress database."
  value       = aws_db_instance.this.db_name
}

output "db_port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret where RDS keeps the master user's credentials. The instances read it at boot."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
