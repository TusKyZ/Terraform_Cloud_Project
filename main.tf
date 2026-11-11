locals {
  # Every resource name starts with this, such as web-school-prod-vpc.
  name_prefix = "${var.project}-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix         = local.name_prefix
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  app_subnet_ids      = module.network.app_subnet_ids
  db_subnet_ids       = module.network.db_subnet_ids
  public_subnet_cidrs = module.network.public_subnet_cidrs
  app_subnet_cidrs    = module.network.app_subnet_cidrs
  db_subnet_cidrs     = module.network.db_subnet_cidrs
}

module "dns" {
  source = "./modules/dns"

  name_prefix = local.name_prefix
  domain_name = var.domain_name
}

module "database" {
  source = "./modules/database"

  name_prefix         = local.name_prefix
  db_subnet_ids       = module.network.db_subnet_ids
  db_sg_id            = module.security.db_sg_id
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

# CloudFront sends this secret in the X-Origin-Verify header, and the ALB
# forwards only requests that carry it. No special characters, because the
# ALB treats * and ? in header values as wildcards.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

module "alb" {
  source = "./modules/alb"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  alb_sg_id            = module.security.alb_sg_id
  alb_certificate_arn  = module.dns.alb_certificate_arn
  zone_id              = module.dns.zone_id
  domain_name          = var.domain_name
  origin_verify_secret = random_password.origin_verify.result
  deletion_protection  = var.alb_deletion_protection
}

module "compute" {
  source = "./modules/compute"

  name_prefix      = local.name_prefix
  app_subnet_ids   = module.network.app_subnet_ids
  app_sg_id        = module.security.app_sg_id
  target_group_arn = module.alb.target_group_arn
  db_address       = module.database.db_address
  db_port          = module.database.db_port
  db_name          = module.database.db_name
  db_secret_arn    = module.database.db_secret_arn
  domain_name      = var.domain_name
  wordpress_image  = var.wordpress_image
}

module "cdn" {
  source = "./modules/cdn"

  name_prefix                = local.name_prefix
  domain_name                = var.domain_name
  origin_fqdn                = module.alb.origin_fqdn
  cloudfront_certificate_arn = module.dns.cloudfront_certificate_arn
  zone_id                    = module.dns.zone_id
  origin_verify_secret       = random_password.origin_verify.result
}
