output "alb_sg_id" {
  description = "ID of the ALB security group."
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "ID of the app security group, for the WordPress instances."
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "ID of the DB security group, for RDS."
  value       = aws_security_group.db.id
}
