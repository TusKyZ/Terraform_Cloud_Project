output "cloudfront_domain_name" {
  description = "Domain name that CloudFront gave the distribution, such as d111111abcdef8.cloudfront.net. The apex and www records point at it."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  description = "ID of the CloudFront distribution, for cache invalidations."
  value       = aws_cloudfront_distribution.this.id
}
