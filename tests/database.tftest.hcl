# Unit tests for modules/database. They plan against a mock AWS provider, so
# they need no AWS credentials and create nothing.

mock_provider "aws" {}

variables {
  name_prefix   = "web-school-prod"
  db_subnet_ids = ["subnet-0db-a", "subnet-0db-b"]
  db_sg_id      = "sg-0db"
}

run "subnet_group_uses_the_db_subnets" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(["subnet-0db-a", "subnet-0db-b"])
    error_message = "The DB subnet group must use the DB subnets."
  }

  assert {
    condition = (
      aws_db_subnet_group.this.name == "web-school-prod-db-subnets" &&
      aws_db_subnet_group.this.tags["Name"] == "web-school-prod-db-subnets"
    )
    error_message = "The DB subnet group's name and Name tag must be <name_prefix>-db-subnets."
  }
}

run "database_is_mysql_8_4_on_db_t3_micro" {
  command = plan

  module {
    source = "./modules/database"
  }

  # A major version only works with automatic minor upgrades: RDS picks the
  # minor version and keeps it patched.
  assert {
    condition = (
      aws_db_instance.this.engine == "mysql" &&
      aws_db_instance.this.engine_version == "8.4" &&
      aws_db_instance.this.auto_minor_version_upgrade == true
    )
    error_message = "The database must be MySQL 8.4 with automatic minor version upgrades."
  }

  assert {
    condition     = aws_db_instance.this.instance_class == "db.t3.micro"
    error_message = "The database must run on db.t3.micro."
  }

  assert {
    condition = (
      aws_db_instance.this.db_name == "wordpress" &&
      aws_db_instance.this.username == "wpadmin" &&
      aws_db_instance.this.port == 3306
    )
    error_message = "The database must be named wordpress, with master user wpadmin, on port 3306."
  }

  assert {
    condition = (
      aws_db_instance.this.identifier == "web-school-prod-db" &&
      aws_db_instance.this.tags["Name"] == "web-school-prod-db"
    )
    error_message = "The database's identifier and Name tag must be <name_prefix>-db."
  }
}

run "database_is_private_behind_the_db_security_group" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "The database must not be publicly accessible."
  }

  assert {
    condition = (
      aws_db_instance.this.vpc_security_group_ids == toset(["sg-0db"]) &&
      aws_db_instance.this.db_subnet_group_name == "web-school-prod-db-subnets"
    )
    error_message = "The database must use only the DB security group, in the DB subnet group."
  }
}

# RDS for MySQL accepts connections without TLS unless a parameter group
# turns on require_secure_transport.
run "database_requires_tls_for_every_connection" {
  command = plan

  module {
    source = "./modules/database"
  }

  # A fixed fake name for the parameter group, which RDS completes from the
  # name prefix.
  override_resource {
    target          = aws_db_parameter_group.this
    override_during = plan
    values = {
      name = "web-school-prod-db-20261024000000000000000001"
    }
  }

  assert {
    condition = aws_db_parameter_group.this.parameter == toset([
      { name = "require_secure_transport", value = "1", apply_method = "immediate" },
    ])
    error_message = "The parameter group must require TLS, and change nothing else."
  }

  assert {
    condition = (
      aws_db_parameter_group.this.family == "mysql8.4" &&
      aws_db_parameter_group.this.family == "mysql${aws_db_instance.this.engine_version}"
    )
    error_message = "The parameter group's family must match the database's engine version."
  }

  assert {
    condition     = aws_db_instance.this.parameter_group_name == "web-school-prod-db-20261024000000000000000001"
    error_message = "The database must use the parameter group that requires TLS."
  }

  # A name prefix, so a replacement can be created while the old group is
  # still in use.
  assert {
    condition = (
      aws_db_parameter_group.this.name_prefix == "web-school-prod-db-" &&
      aws_db_parameter_group.this.tags["Name"] == "web-school-prod-db-params"
    )
    error_message = "The parameter group must use the name prefix <name_prefix>-db- and the Name tag <name_prefix>-db-params."
  }
}

run "database_is_multi_az_with_encrypted_gp3_storage" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true
    error_message = "The database must be Multi-AZ."
  }

  # 20 GB is the gp3 minimum; storage autoscaling grows it up to 100 GB.
  assert {
    condition = (
      aws_db_instance.this.storage_type == "gp3" &&
      aws_db_instance.this.allocated_storage == 20 &&
      aws_db_instance.this.max_allocated_storage == 100
    )
    error_message = "Storage must be gp3, starting at 20 GB and growing up to 100 GB."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "Storage must be encrypted."
  }
}

run "master_password_is_managed_by_rds" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "RDS must create and manage the master password in Secrets Manager."
  }

  # With a managed password, Terraform must never set one itself.
  assert {
    condition     = aws_db_instance.this.password == null && aws_db_instance.this.password_wo == null
    error_message = "The configuration must not set a master password."
  }
}

# The instances pick up a rotated password within a minute. Early on Sunday
# in Jakarta, the errors of that minute reach few visitors.
run "master_password_rotates_early_on_sunday_in_jakarta" {
  command = plan

  module {
    source = "./modules/database"
  }

  # A fixed fake ARN for the secret that RDS creates with the database.
  override_resource {
    target          = aws_db_instance.this
    override_during = plan
    values = {
      master_user_secret = [
        {
          kms_key_id    = "arn:aws:kms:ap-southeast-3:111122223333:key/test"
          secret_arn    = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
          secret_status = "active"
        },
      ]
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.master_password.secret_id == "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
    error_message = "The schedule must apply to the master user secret that RDS manages."
  }

  # Saturday 19:00 to 21:00 UTC is Sunday 02:00 to 04:00 in Jakarta (UTC+7).
  assert {
    condition = (
      aws_secretsmanager_secret_rotation.master_password.rotation_rules[0].schedule_expression == "cron(0 19 ? * SAT *)" &&
      aws_secretsmanager_secret_rotation.master_password.rotation_rules[0].duration == "2h"
    )
    error_message = "The password must rotate between 02:00 and 04:00 on Sunday, Jakarta time."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.master_password.rotate_immediately == false
    error_message = "Setting the schedule must not rotate the password straight away."
  }
}

run "backups_are_kept_for_7_days" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition = (
      aws_db_instance.this.backup_retention_period == 7 &&
      aws_db_instance.this.copy_tags_to_snapshot == true
    )
    error_message = "Automated backups must be kept for 7 days, and snapshots must get the database's tags."
  }
}

run "error_log_goes_to_cloudwatch_logs" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.enabled_cloudwatch_logs_exports == toset(["error"])
    error_message = "The database must publish its error log, and only that log, to CloudWatch Logs."
  }
}

# RDS publishes the error log to /aws/rds/instance/<identifier>/error. The
# module creates that log group itself, so the log has a retention period.
run "error_log_is_kept_for_365_days" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.error.name == "/aws/rds/instance/web-school-prod-db/error" &&
      aws_cloudwatch_log_group.error.name == "/aws/rds/instance/${aws_db_instance.this.identifier}/error"
    )
    error_message = "The log group must be the one RDS publishes the database's error log to."
  }

  assert {
    condition     = aws_cloudwatch_log_group.error.retention_in_days == 365
    error_message = "The error log must be kept for 365 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.error.tags["Name"] == "web-school-prod-db-error-log"
    error_message = "The log group's Name tag must be <name_prefix>-db-error-log."
  }
}

run "deletion_protection_and_final_snapshot_are_on_by_default" {
  command = plan

  module {
    source = "./modules/database"
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection == true
    error_message = "Deletion protection must be on by default."
  }

  assert {
    condition = (
      aws_db_instance.this.skip_final_snapshot == false &&
      aws_db_instance.this.final_snapshot_identifier == "web-school-prod-db-final"
    )
    error_message = "Deleting the database must take a final snapshot, <name_prefix>-db-final, by default."
  }
}

run "throwaway_deploy_can_turn_off_deletion_protection_and_final_snapshot" {
  command = plan

  module {
    source = "./modules/database"
  }

  variables {
    deletion_protection = false
    skip_final_snapshot = true
  }

  assert {
    condition = (
      aws_db_instance.this.deletion_protection == false &&
      aws_db_instance.this.skip_final_snapshot == true
    )
    error_message = "deletion_protection and skip_final_snapshot must reach the database."
  }
}

run "outputs_are_the_connection_details_and_the_secret" {
  command = plan

  module {
    source = "./modules/database"
  }

  # Fixed fake values for what RDS only knows once the database exists.
  override_resource {
    target          = aws_db_instance.this
    override_during = plan
    values = {
      address = "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com"
      master_user_secret = [
        {
          kms_key_id    = "arn:aws:kms:ap-southeast-3:111122223333:key/test"
          secret_arn    = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
          secret_status = "active"
        },
      ]
    }
  }

  assert {
    condition = (
      output.db_address == "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com" &&
      output.db_port == 3306 &&
      output.db_name == "wordpress"
    )
    error_message = "db_address, db_port and db_name must come from the database."
  }

  assert {
    condition     = output.db_secret_arn == "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
    error_message = "db_secret_arn must be the ARN of the secret that RDS manages for the master user."
  }
}

# RDS needs a subnet group that covers at least two AZs.
run "single_db_subnet_is_rejected" {
  command = plan

  module {
    source = "./modules/database"
  }

  variables {
    db_subnet_ids = ["subnet-0db-a"]
  }

  expect_failures = [var.db_subnet_ids]
}
