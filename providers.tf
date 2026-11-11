# One provider for the whole stack. CloudFront and Route 53 are global
# services. The CloudFront certificate and its validation are the only
# resources in another Region: CloudFront only accepts certificates from
# us-east-1, so they set region = "us-east-1" on the resource itself
# (supported from AWS provider 6.0).
provider "aws" {
  region = var.aws_region

  # Added to every resource that supports tags, for cost tracking and
  # ownership. The Auto Scaling group is the exception: the compute module
  # tags it and the instances it launches.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}
