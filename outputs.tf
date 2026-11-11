output "alb_dns_name" {
  description = "DNS name of the ALB, for troubleshooting. Its security group admits only CloudFront, so a request from anywhere else times out. CloudFront connects through the origin name, such as origin.webschool.example."
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "Name of the Auto Scaling group that runs the WordPress instances."
  value       = module.compute.asg_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution, for cache invalidations."
  value       = module.cdn.distribution_id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution, such as d111111abcdef8.cloudfront.net. The apex and www records point at it."
  value       = module.cdn.cloudfront_domain_name
}

output "db_endpoint" {
  description = "Host name and port of the database, in the form WordPress connects to. Only the app instances can reach it."
  value       = "${module.database.db_address}:${module.database.db_port}"
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret that holds the database's master user name and password. The password itself stays in Secrets Manager."
  value       = module.database.db_secret_arn
}

output "name_servers" {
  description = "Name servers of the hosted zone. The domain's registrar must list them before ACM can validate the certificates and visitors can reach the site."
  value       = module.dns.name_servers
}

output "website_url" {
  description = "Address of the site. It answers once the registrar lists the name servers and the full apply has finished."
  value       = "https://${var.domain_name}"
}
