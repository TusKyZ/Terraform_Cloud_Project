output "alb_dns_name" {
  description = "DNS name of the ALB. CloudFront does not use it: it connects through origin_fqdn, which the ALB's certificate covers."
  value       = aws_lb.this.dns_name
}

output "origin_fqdn" {
  description = "Origin name that CloudFront connects to, such as origin.webschool.example."
  value       = aws_route53_record.origin.fqdn
}

output "target_group_arn" {
  description = "ARN of the target group, for the Auto Scaling group to register the WordPress instances in."
  value       = aws_lb_target_group.app.arn
}
