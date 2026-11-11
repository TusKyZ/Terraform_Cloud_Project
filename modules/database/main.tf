locals {
  # The database's name. RDS also puts it in the name of the log group that
  # it publishes the error log to.
  identifier = "${var.name_prefix}-db"

  # The parameter group's family must match the engine version.
  engine_version = "8.4"
}

# RDS places the database and its Multi-AZ standby in these subnets, which
# span two AZs and have no route to the internet.
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

# RDS publishes the error log to this log group. Terraform creates it before
# the database so that it has a retention period: a log group that RDS
# creates itself keeps logs forever. CloudWatch Logs encrypts log data at
# rest.
resource "aws_cloudwatch_log_group" "error" {
  name              = "/aws/rds/instance/${local.identifier}/error"
  retention_in_days = 365

  tags = {
    Name = "${local.identifier}-error-log"
  }
}

# Requires TLS for every connection, so queries and the password never cross
# the network in clear text. RDS for MySQL leaves require_secure_transport
# off by default. WordPress connects with TLS (MYSQL_CLIENT_FLAGS, set by the
# compute module).
resource "aws_db_parameter_group" "this" {
  name_prefix = "${local.identifier}-"
  family      = "mysql${local.engine_version}"
  description = "TLS required for every connection to ${local.identifier}"

  # A dynamic parameter, so it takes effect without a reboot.
  parameter {
    name         = "require_secure_transport"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name = "${local.identifier}-params"
  }

  # RDS cannot delete a parameter group that a database still uses, so a
  # replacement, such as one for a new engine version, is created first.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = local.identifier
  engine     = "mysql"
  # MySQL 8.0 left RDS standard support on 31 July 2026; 8.4 has it until
  # 31 July 2029. With only the major version given, RDS picks the minor
  # version and applies minor upgrades itself.
  engine_version             = local.engine_version
  auto_minor_version_upgrade = true
  instance_class             = "db.t3.micro"
  parameter_group_name       = aws_db_parameter_group.this.name

  db_name  = "wordpress"
  username = "wpadmin"
  port     = 3306

  # RDS creates the master password, keeps it in Secrets Manager and rotates
  # it, so it never appears in this code or in the Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false

  # A standby in the other AZ takes over if the primary or its AZ fails.
  multi_az = true

  # 20 GB is the gp3 minimum; storage autoscaling grows it up to 100 GB.
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # MySQL writes its error log by default. Publishing it to CloudWatch Logs
  # keeps a searchable copy outside the instance.
  enabled_cloudwatch_logs_exports = ["error"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${local.identifier}-final"

  tags = {
    Name = local.identifier
  }

  # If RDS started publishing first, it would create the log group itself and
  # Terraform's create would then fail on the name.
  depends_on = [aws_cloudwatch_log_group.error]
}

# RDS rotates the master password every 7 days, at any time of day. This
# moves each rotation to early Sunday morning in Jakarta, when school sites
# are quiet. Rotation takes about a minute, and the instances pick up the new
# password within a minute after it, so any errors in between reach few
# visitors.
resource "aws_secretsmanager_secret_rotation" "master_password" {
  secret_id = aws_db_instance.this.master_user_secret[0].secret_arn

  # Wait for the next window rather than rotate as soon as this is applied.
  rotate_immediately = false

  rotation_rules {
    # Saturday 19:00 to 21:00 UTC is Sunday 02:00 to 04:00 in Jakarta (UTC+7).
    schedule_expression = "cron(0 19 ? * SAT *)"
    duration            = "2h"
  }
}
