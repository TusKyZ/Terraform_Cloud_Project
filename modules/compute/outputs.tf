output "asg_name" {
  description = "Name of the Auto Scaling group that runs the WordPress instances."
  value       = aws_autoscaling_group.this.name
}

output "instance_role_arn" {
  description = "ARN of the IAM role that the WordPress instances run as."
  value       = aws_iam_role.instance.arn
}
