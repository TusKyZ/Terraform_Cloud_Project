# Unit tests for modules/compute. They plan against a mock AWS provider, so
# they need no AWS credentials and create nothing.

mock_provider "aws" {}

# The mock provider fills data sources with random strings, and the provider
# still checks that a policy ARN is a valid ARN. So every run gets the real
# ARN of AWS's managed Session Manager policy.
override_data {
  target = data.aws_iam_policy.ssm_core
  values = {
    arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# A fixed fake ARN for the WordPress keys secret, which the instance policy
# and user_data name. A secret's ID is its ARN.
override_resource {
  target          = aws_secretsmanager_secret.wordpress_keys
  override_during = plan
  values = {
    arn = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test"
    id  = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test"
  }
}

# Fixed fake values for the other data sources: the AMI that the SSM
# parameter points to, the Region, and the provider's default tags.
override_data {
  target = data.aws_ssm_parameter.al2023
  values = {
    insecure_value = "ami-0a1b2c3d4e5f60718"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    region = "ap-southeast-3"
  }
}

override_data {
  target = data.aws_default_tags.current
  values = {
    tags = {
      Project     = "web-school"
      Environment = "prod"
      Owner       = "Example School Group"
      ManagedBy   = "terraform"
    }
  }
}

variables {
  name_prefix      = "web-school-prod"
  db_secret_arn    = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test"
  app_sg_id        = "sg-0app"
  db_address       = "web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com"
  db_port          = 3306
  db_name          = "wordpress"
  domain_name      = "webschool.example"
  wordpress_image  = "public.ecr.aws/docker/library/wordpress:7.1.3-php8.3-apache"
  app_subnet_ids   = ["subnet-0app-a", "subnet-0app-b"]
  target_group_arn = "arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"
}

run "only_ec2_can_assume_the_instance_role" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = jsondecode(aws_iam_role.instance.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }]
    }
    error_message = "Only EC2 may assume the instance role."
  }

  assert {
    condition = (
      aws_iam_role.instance.name_prefix == "web-school-prod-app-" &&
      aws_iam_role.instance.tags["Name"] == "web-school-prod-app-role"
    )
    error_message = "The instance role must use the name prefix <name_prefix>-app- and the Name tag <name_prefix>-app-role."
  }
}

run "instances_use_session_manager_instead_of_ssh" {
  command = plan

  module {
    source = "./modules/compute"
  }

  # A fixed fake name, so the attachment's and the profile's role can be
  # checked.
  override_resource {
    target          = aws_iam_role.instance
    override_during = plan
    values = {
      name = "web-school-prod-app-test"
    }
  }

  assert {
    condition = (
      data.aws_iam_policy.ssm_core.name == "AmazonSSMManagedInstanceCore" &&
      aws_iam_role_policy_attachment.ssm_core.role == "web-school-prod-app-test" &&
      aws_iam_role_policy_attachment.ssm_core.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    )
    error_message = "The instance role must have AWS's managed Session Manager policy, AmazonSSMManagedInstanceCore."
  }

  assert {
    condition = (
      aws_iam_instance_profile.instance.role == "web-school-prod-app-test" &&
      aws_iam_instance_profile.instance.name_prefix == "web-school-prod-app-" &&
      aws_iam_instance_profile.instance.tags["Name"] == "web-school-prod-app-profile"
    )
    error_message = "The instance profile must carry the instance role, with the name prefix <name_prefix>-app- and the Name tag <name_prefix>-app-profile."
  }
}

# Least privilege: one statement with one read-only action on two exact
# secrets.
run "instances_can_read_only_their_two_secrets" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.read_secrets.policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test",
          "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test",
        ]
      }]
    }
    error_message = "The instances may only read the database secret and the WordPress keys secret."
  }
}

run "wordpress_keys_are_generated_and_kept_out_of_the_state" {
  command = plan

  module {
    source = "./modules/compute"
  }

  # wp-config.php defines these eight. Any left unset would get a random
  # value per container, and logins would break between instances.
  assert {
    condition = local.wordpress_key_names == [
      "AUTH_KEY",
      "SECURE_AUTH_KEY",
      "LOGGED_IN_KEY",
      "NONCE_KEY",
      "AUTH_SALT",
      "SECURE_AUTH_SALT",
      "LOGGED_IN_SALT",
      "NONCE_SALT",
    ]
    error_message = "The secret must hold all eight WordPress keys and salts."
  }

  # A write-only value never reaches the plan or the state. Terraform sends it
  # again only when the version number changes.
  assert {
    condition = (
      aws_secretsmanager_secret_version.wordpress_keys.secret_id == "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test" &&
      aws_secretsmanager_secret_version.wordpress_keys.secret_string == null &&
      aws_secretsmanager_secret_version.wordpress_keys.secret_string_wo_version == 1
    )
    error_message = "The keys must go into the secret as a write-only value, version 1."
  }

  # A name prefix, so a replacement does not clash with the old secret's name
  # during its deletion window.
  assert {
    condition = (
      aws_secretsmanager_secret.wordpress_keys.name_prefix == "web-school-prod-wordpress-keys-" &&
      aws_secretsmanager_secret.wordpress_keys.tags["Name"] == "web-school-prod-wordpress-keys"
    )
    error_message = "The keys secret must use the name prefix <name_prefix>-wordpress-keys- and the Name tag <name_prefix>-wordpress-keys."
  }
}

run "launch_template_uses_the_latest_amazon_linux_2023_by_default" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition     = data.aws_ssm_parameter.al2023.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "The AMI must come from AWS's public SSM parameter for the latest Amazon Linux 2023 on x86_64."
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0a1b2c3d4e5f60718"
    error_message = "Without ami_id, the launch template must use the AMI from the SSM parameter."
  }

  assert {
    condition = (
      aws_launch_template.this.name == "web-school-prod-app-lt" &&
      aws_launch_template.this.tags["Name"] == "web-school-prod-app-lt"
    )
    error_message = "The launch template's name and Name tag must be <name_prefix>-app-lt."
  }
}

run "ami_id_pins_an_exact_ami" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0fedcba9876543210"
    error_message = "ami_id must replace the AMI from the SSM parameter."
  }
}

run "instances_are_t3_small_without_a_key_pair" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition     = aws_launch_template.this.instance_type == "t3.small"
    error_message = "The instances must be t3.small by default."
  }

  # No key pair and no SSH: Session Manager is the only way in.
  assert {
    condition     = aws_launch_template.this.key_name == null
    error_message = "The instances must have no key pair."
  }
}

# IMDSv2 only. A hop limit of 1 stops the metadata response at the Docker
# bridge, so the WordPress container cannot take the instance role's
# credentials.
run "instances_require_imdsv2_with_a_hop_limit_of_1" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      aws_launch_template.this.metadata_options[0].http_endpoint == "enabled" &&
      aws_launch_template.this.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.this.metadata_options[0].http_put_response_hop_limit == 1
    )
    error_message = "The instances must require IMDSv2 with a hop limit of 1."
  }
}

run "instances_get_no_public_ip_and_only_the_app_security_group" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      length(aws_launch_template.this.network_interfaces) == 1 &&
      aws_launch_template.this.network_interfaces[0].associate_public_ip_address == "false" &&
      aws_launch_template.this.network_interfaces[0].security_groups == toset(["sg-0app"])
    )
    error_message = "The instances must get no public IP address and only the app security group."
  }
}

run "root_volume_is_encrypted_gp3" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      length(aws_launch_template.this.block_device_mappings) == 1 &&
      aws_launch_template.this.block_device_mappings[0].device_name == "/dev/xvda" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "gp3" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 20 &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].delete_on_termination == "true"
    )
    error_message = "The root volume must be an encrypted 20 GB gp3 volume, deleted with the instance."
  }
}

run "instances_run_as_the_instance_profile" {
  command = plan

  module {
    source = "./modules/compute"
  }

  override_resource {
    target          = aws_iam_instance_profile.instance
    override_during = plan
    values = {
      arn = "arn:aws:iam::111122223333:instance-profile/web-school-prod-app-test"
    }
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].arn == "arn:aws:iam::111122223333:instance-profile/web-school-prod-app-test"
    error_message = "The instances must run with the instance profile."
  }
}

# The provider's default tags do not reach what an Auto Scaling group
# launches, so the launch template tags the instances and their volumes.
run "instances_and_their_volumes_get_the_stack_tags" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      length(aws_launch_template.this.tag_specifications) == 2 &&
      aws_launch_template.this.tag_specifications[0].resource_type == "instance" &&
      aws_launch_template.this.tag_specifications[1].resource_type == "volume"
    )
    error_message = "The launch template must tag the instances and their volumes."
  }

  assert {
    condition = alltrue([
      for spec in aws_launch_template.this.tag_specifications : spec.tags == tomap({
        Project     = "web-school"
        Environment = "prod"
        Owner       = "Example School Group"
        ManagedBy   = "terraform"
        Name        = "web-school-prod-app"
      })
    ])
    error_message = "The instances and volumes must get the provider's default tags and the Name tag <name_prefix>-app."
  }
}

run "user_data_runs_the_pinned_image_on_port_80" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), " --publish 80:80 ")
    error_message = "The container must serve WordPress on the instance's port 80."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), " public.ecr.aws/docker/library/wordpress:7.1.3-php8.3-apache\n")
    error_message = "The container must run the image in wordpress_image."
  }

  # The host network would let the container reach the instance metadata
  # despite the hop limit.
  assert {
    condition     = !can(regex("--net(work)?[= ]host", base64decode(aws_launch_template.this.user_data)))
    error_message = "The container must stay on Docker's default bridge network."
  }
}

run "user_data_hands_the_secrets_to_wordpress_only_through_files" {
  command = plan

  module {
    source = "./modules/compute"
  }

  # Command tracing would print the secrets into the cloud-init log.
  assert {
    condition     = !can(regex("set -[a-z]*x|xtrace", base64decode(aws_launch_template.this.user_data)))
    error_message = "user_data must not trace its commands (set -x)."
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.this.user_data), "\ndb_secret_arn='arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test'\n") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "\nkeys_secret_arn='arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test'\n") &&
      strcontains(base64decode(aws_launch_template.this.user_data), " --region ap-southeast-3 ")
    )
    error_message = "The instances must read the database secret and the keys secret from Secrets Manager."
  }

  # The image's wp-config.php reads each <name>_FILE setting from that file.
  assert {
    condition = alltrue([
      for name in concat(["DB_USER", "DB_PASSWORD"], local.wordpress_key_names) :
      strcontains(base64decode(aws_launch_template.this.user_data), "\nWORDPRESS_${name}_FILE=/run/secrets/wordpress/${name}\n")
    ])
    error_message = "WordPress must read the database credentials and all eight keys from files."
  }

  assert {
    condition     = !can(regex("WORDPRESS_(DB_USER|DB_PASSWORD|[A-Z_]+_(KEY|SALT))=", base64decode(aws_launch_template.this.user_data)))
    error_message = "No secret may reach the container as a plain environment variable."
  }
}

# RDS rotates the master password every week. The files are rewritten every
# minute, and the container sees each new file because it mounts the whole
# folder, not single files.
run "user_data_refreshes_the_secret_files_every_minute" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), "\nOnCalendar=minutely\n")
    error_message = "A systemd timer must refresh the secret files every minute."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), " --volume /run/wordpress:/run/secrets/wordpress:ro ")
    error_message = "The container must mount the folder that holds the secret files, read-only."
  }

  # Write to a staging folder, then rename each file over the old one, so
  # WordPress never reads a half-written file.
  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), "mv -f \"$file\" \"$dir/\"")
    error_message = "Each secret file must be replaced in one atomic rename."
  }

  # A failed fetch, or a missing, null or empty value, must leave the old
  # files in place. tests/integration runs these cases for real.
  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), "[ -n \"$value\" ] && [ \"$value\" != \"null\" ] || return 1")
    error_message = "Every secret value must be checked before any file is replaced."
  }
}

run "wordpress_uses_the_site_domain_and_tls_to_the_database" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.this.user_data), "\nWORDPRESS_DB_HOST=web-school-prod-db.abc123.ap-southeast-3.rds.amazonaws.com:3306\n") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "\nWORDPRESS_DB_NAME=wordpress\n")
    )
    error_message = "WordPress must connect to the database's address, port and name."
  }

  # WordPress sees the Host origin.<domain>, so it needs the public address
  # set explicitly.
  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), "define('WP_HOME', 'https://webschool.example'); define('WP_SITEURL', 'https://webschool.example');")
    error_message = "WP_HOME and WP_SITEURL must be https://<domain_name>."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.this.user_data), "define('MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL);")
    error_message = "WordPress must connect to the database over TLS."
  }
}

# Each instance has its own copy of WordPress, so code installed or updated
# from the dashboard would reach one instance only. New code comes with a new
# image tag.
run "wordpress_cannot_change_its_own_code" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.this.user_data), "define('DISALLOW_FILE_MODS', true);") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "define('AUTOMATIC_UPDATER_DISABLED', true);")
    )
    error_message = "WordPress must not install plugins, themes or updates by itself."
  }
}

# A tag such as 7.1.3-php8.3-apache fixes the WordPress, PHP and Apache
# versions. It must be the Apache variant, the one that serves port 80.
run "docker_hub_form_of_the_image_is_accepted" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    wordpress_image = "wordpress:7.1.3-php8.3-apache"
  }
}

run "latest_image_tag_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    wordpress_image = "wordpress:latest"
  }

  expect_failures = [var.wordpress_image]
}

run "image_without_a_tag_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    wordpress_image = "public.ecr.aws/docker/library/wordpress"
  }

  expect_failures = [var.wordpress_image]
}

# 7.1-php8.3-apache moves to each new 7.1.x release.
run "floating_minor_version_tag_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    wordpress_image = "wordpress:7.1-php8.3-apache"
  }

  expect_failures = [var.wordpress_image]
}

run "fpm_variant_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    wordpress_image = "wordpress:7.1.3-php8.3-fpm"
  }

  expect_failures = [var.wordpress_image]
}

run "malformed_ami_id_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    ami_id = "ami-123"
  }

  expect_failures = [var.ami_id]
}

# The same rule as the dns module's, so the module refuses a bad name when
# used on its own too: the name goes into WordPress's PHP settings.
run "uppercase_domain_name_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    domain_name = "WebSchool.example"
  }

  expect_failures = [var.domain_name]
}

run "group_runs_1_to_4_instances_across_both_app_subnets" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      aws_autoscaling_group.this.min_size == 1 &&
      aws_autoscaling_group.this.max_size == 4
    )
    error_message = "The group must run at least 1 and at most 4 instances by default."
  }

  assert {
    condition     = aws_autoscaling_group.this.vpc_zone_identifier == toset(["subnet-0app-a", "subnet-0app-b"])
    error_message = "The group must launch instances in both app subnets."
  }

  assert {
    condition     = aws_autoscaling_group.this.name == "web-school-prod-app-asg"
    error_message = "The group's name must be <name_prefix>-app-asg."
  }
}

# The group replaces any instance that fails the ALB's health check, after a
# grace period for installing Docker and starting WordPress.
run "group_replaces_instances_that_fail_the_alb_health_check" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition     = aws_autoscaling_group.this.target_group_arns == toset(["arn:aws:elasticloadbalancing:ap-southeast-3:111122223333:targetgroup/app-test/0"])
    error_message = "The group must register its instances in the ALB's target group."
  }

  assert {
    condition = (
      aws_autoscaling_group.this.health_check_type == "ELB" &&
      aws_autoscaling_group.this.health_check_grace_period == 300
    )
    error_message = "The group must use the ALB's health checks, with a 300-second grace period."
  }
}

run "group_launches_the_newest_launch_template_version" {
  command = plan

  module {
    source = "./modules/compute"
  }

  override_resource {
    target          = aws_launch_template.this
    override_during = plan
    values = {
      id             = "lt-0test"
      latest_version = 3
    }
  }

  # A version number, not "$Latest": only a changed number starts the
  # instance refresh.
  assert {
    condition = (
      length(aws_autoscaling_group.this.launch_template) == 1 &&
      aws_autoscaling_group.this.launch_template[0].id == "lt-0test" &&
      aws_autoscaling_group.this.launch_template[0].version == "3"
    )
    error_message = "The group must launch the launch template's newest version, by number."
  }
}

# New instances are launched and healthy before old ones are terminated, so
# capacity never drops during a rollout.
run "launch_template_changes_roll_out_with_an_instance_refresh" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      length(aws_autoscaling_group.this.instance_refresh) == 1 &&
      aws_autoscaling_group.this.instance_refresh[0].strategy == "Rolling" &&
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 100 &&
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].max_healthy_percentage == 200
    )
    error_message = "A launch template change must roll out by launching new instances before terminating old ones."
  }
}

# The provider's default tags do not apply to Auto Scaling groups.
run "group_gets_the_stack_tags" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = aws_autoscaling_group.this.tag == toset([
      { key = "Project", value = "web-school", propagate_at_launch = false },
      { key = "Environment", value = "prod", propagate_at_launch = false },
      { key = "Owner", value = "Example School Group", propagate_at_launch = false },
      { key = "ManagedBy", value = "terraform", propagate_at_launch = false },
      { key = "Name", value = "web-school-prod-app-asg", propagate_at_launch = false },
    ])
    error_message = "The group must get the provider's default tags and the Name tag <name_prefix>-app-asg, kept off the instances, which the launch template tags."
  }
}

run "min_size_above_max_size_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    min_size = 5
  }

  expect_failures = [var.min_size]
}

run "max_size_of_0_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    min_size = 0
    max_size = 0
  }

  expect_failures = [var.max_size]
}

# One subnet would put every instance in one AZ.
run "single_app_subnet_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    app_subnet_ids = ["subnet-0app-a"]
  }

  expect_failures = [var.app_subnet_ids]
}

run "scale_out_policy_adds_one_instance" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      aws_autoscaling_policy.scale_out.autoscaling_group_name == "web-school-prod-app-asg" &&
      aws_autoscaling_policy.scale_out.policy_type == "SimpleScaling" &&
      aws_autoscaling_policy.scale_out.adjustment_type == "ChangeInCapacity" &&
      aws_autoscaling_policy.scale_out.scaling_adjustment == 1
    )
    error_message = "The scale-out policy must add one instance to the group."
  }

  assert {
    condition = (
      aws_autoscaling_policy.scale_out.cooldown == 300 &&
      aws_autoscaling_policy.scale_out.name == "web-school-prod-app-scale-out"
    )
    error_message = "The scale-out policy must wait 300 seconds between changes and be named <name_prefix>-app-scale-out."
  }
}

run "scale_in_policy_removes_one_instance" {
  command = plan

  module {
    source = "./modules/compute"
  }

  assert {
    condition = (
      aws_autoscaling_policy.scale_in.autoscaling_group_name == "web-school-prod-app-asg" &&
      aws_autoscaling_policy.scale_in.policy_type == "SimpleScaling" &&
      aws_autoscaling_policy.scale_in.adjustment_type == "ChangeInCapacity" &&
      aws_autoscaling_policy.scale_in.scaling_adjustment == -1
    )
    error_message = "The scale-in policy must remove one instance from the group."
  }

  assert {
    condition = (
      aws_autoscaling_policy.scale_in.cooldown == 300 &&
      aws_autoscaling_policy.scale_in.name == "web-school-prod-app-scale-in"
    )
    error_message = "The scale-in policy must wait 300 seconds between changes and be named <name_prefix>-app-scale-in."
  }
}

# 6 periods of 300 seconds = 30 minutes. EC2 basic monitoring publishes CPU
# every 5 minutes, so a shorter period would have no data.
run "cpu_above_80_percent_for_30_minutes_adds_an_instance" {
  command = plan

  module {
    source = "./modules/compute"
  }

  override_resource {
    target          = aws_autoscaling_policy.scale_out
    override_during = plan
    values = {
      arn = "arn:aws:autoscaling:ap-southeast-3:111122223333:scalingPolicy:11111111-2222-3333-4444-555555555555:autoScalingGroupName/web-school-prod-app-asg:policyName/web-school-prod-app-scale-out"
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_high.namespace == "AWS/EC2" &&
      aws_cloudwatch_metric_alarm.cpu_high.metric_name == "CPUUtilization" &&
      aws_cloudwatch_metric_alarm.cpu_high.statistic == "Average" &&
      aws_cloudwatch_metric_alarm.cpu_high.dimensions == tomap({ AutoScalingGroupName = "web-school-prod-app-asg" })
    )
    error_message = "The alarm must watch the group's average CPU."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_high.comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.cpu_high.threshold == 80
    )
    error_message = "The alarm must fire above 80%."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_high.period == 300 &&
      aws_cloudwatch_metric_alarm.cpu_high.evaluation_periods == 6 &&
      aws_cloudwatch_metric_alarm.cpu_high.datapoints_to_alarm == 6
    )
    error_message = "The alarm must need 30 minutes of breaching data: 6 of 6 periods of 300 seconds."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_high.alarm_actions == toset(["arn:aws:autoscaling:ap-southeast-3:111122223333:scalingPolicy:11111111-2222-3333-4444-555555555555:autoScalingGroupName/web-school-prod-app-asg:policyName/web-school-prod-app-scale-out"]) &&
      aws_cloudwatch_metric_alarm.cpu_high.alarm_name == "web-school-prod-app-cpu-high"
    )
    error_message = "The alarm, <name_prefix>-app-cpu-high, must call only the scale-out policy."
  }
}

run "cpu_below_40_percent_for_30_minutes_removes_an_instance" {
  command = plan

  module {
    source = "./modules/compute"
  }

  override_resource {
    target          = aws_autoscaling_policy.scale_in
    override_during = plan
    values = {
      arn = "arn:aws:autoscaling:ap-southeast-3:111122223333:scalingPolicy:66666666-7777-8888-9999-000000000000:autoScalingGroupName/web-school-prod-app-asg:policyName/web-school-prod-app-scale-in"
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_low.namespace == "AWS/EC2" &&
      aws_cloudwatch_metric_alarm.cpu_low.metric_name == "CPUUtilization" &&
      aws_cloudwatch_metric_alarm.cpu_low.statistic == "Average" &&
      aws_cloudwatch_metric_alarm.cpu_low.dimensions == tomap({ AutoScalingGroupName = "web-school-prod-app-asg" })
    )
    error_message = "The alarm must watch the group's average CPU."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_low.comparison_operator == "LessThanThreshold" &&
      aws_cloudwatch_metric_alarm.cpu_low.threshold == 40
    )
    error_message = "The alarm must fire below 40%."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_low.period == 300 &&
      aws_cloudwatch_metric_alarm.cpu_low.evaluation_periods == 6 &&
      aws_cloudwatch_metric_alarm.cpu_low.datapoints_to_alarm == 6
    )
    error_message = "The alarm must need 30 minutes of breaching data: 6 of 6 periods of 300 seconds."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu_low.alarm_actions == toset(["arn:aws:autoscaling:ap-southeast-3:111122223333:scalingPolicy:66666666-7777-8888-9999-000000000000:autoScalingGroupName/web-school-prod-app-asg:policyName/web-school-prod-app-scale-in"]) &&
      aws_cloudwatch_metric_alarm.cpu_low.alarm_name == "web-school-prod-app-cpu-low"
    )
    error_message = "The alarm, <name_prefix>-app-cpu-low, must call only the scale-in policy."
  }
}

run "cpu_threshold_above_100_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    scale_out_cpu_threshold = 101
  }

  expect_failures = [var.scale_out_cpu_threshold]
}

run "negative_cpu_threshold_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    scale_in_cpu_threshold = -1
  }

  expect_failures = [var.scale_in_cpu_threshold]
}

# With equal thresholds the group could add and remove instances in turn.
run "scale_in_threshold_not_below_scale_out_is_rejected" {
  command = plan

  module {
    source = "./modules/compute"
  }

  variables {
    scale_in_cpu_threshold = 80
  }

  expect_failures = [var.scale_in_cpu_threshold]
}

run "outputs_are_the_group_name_and_the_role_arn" {
  command = plan

  module {
    source = "./modules/compute"
  }

  # A fixed fake ARN for what IAM only knows once the role exists.
  override_resource {
    target          = aws_iam_role.instance
    override_during = plan
    values = {
      arn  = "arn:aws:iam::111122223333:role/web-school-prod-app-test"
      name = "web-school-prod-app-test"
    }
  }

  assert {
    condition = (
      output.asg_name == "web-school-prod-app-asg" &&
      output.instance_role_arn == "arn:aws:iam::111122223333:role/web-school-prod-app-test"
    )
    error_message = "The outputs must be the Auto Scaling group's name and the instance role's ARN."
  }
}
