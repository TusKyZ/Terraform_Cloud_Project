locals {
  # WordPress's eight authentication keys and salts. They sign the login
  # cookies, so every instance must use the same values.
  wordpress_key_names = [
    "AUTH_KEY",
    "SECURE_AUTH_KEY",
    "LOGGED_IN_KEY",
    "NONCE_KEY",
    "AUTH_SALT",
    "SECURE_AUTH_SALT",
    "LOGGED_IN_SALT",
    "NONCE_SALT",
  ]

  # The provider's default tags do not reach what an Auto Scaling group
  # launches, so the launch template copies them onto the instances and
  # their volumes.
  instance_tags = merge(data.aws_default_tags.current.tags, {
    Name = "${var.name_prefix}-app"
  })
}

data "aws_default_tags" "current" {}

data "aws_region" "current" {}

# The role the WordPress instances run as. It allows Session Manager, which
# replaces SSH, and reading the instances' two secrets, nothing else.
resource "aws_iam_role" "instance" {
  name_prefix = "${var.name_prefix}-app-"
  description = "WordPress instances: Session Manager and read access to their two secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-app-role"
  }
}

# AWS's managed policy for Session Manager, looked up by name.
data "aws_iam_policy" "ssm_core" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

# Read access to exactly two secrets: the database credentials and the
# WordPress keys. The AWS managed key that encrypts both lets any principal
# allowed to read a secret decrypt it, so no KMS permission is needed.
resource "aws_iam_role_policy" "read_secrets" {
  name = "read-wordpress-secrets"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [var.db_secret_arn, aws_secretsmanager_secret.wordpress_keys.arn]
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name_prefix}-app-"
  role        = aws_iam_role.instance.name

  tags = {
    Name = "${var.name_prefix}-app-profile"
  }
}

# The WordPress keys and salts, as one JSON object. A name prefix, so that a
# replacement secret does not clash with the old one's name while the old one
# waits out its deletion window.
resource "aws_secretsmanager_secret" "wordpress_keys" {
  name_prefix = "${var.name_prefix}-wordpress-keys-"
  description = "WordPress authentication keys and salts, shared by every instance"

  tags = {
    Name = "${var.name_prefix}-wordpress-keys"
  }
}

# Ephemeral: Terraform generates the values in memory and never stores them.
# 64 letters and digits give each key about 380 bits of randomness.
ephemeral "random_password" "wordpress_keys" {
  for_each = toset(local.wordpress_key_names)

  length  = 64
  special = false
}

# secret_string_wo is write-only, so the keys never reach the plan or the
# state. Terraform sends them only when secret_string_wo_version changes:
# raise it to replace every key, which logs every user out.
resource "aws_secretsmanager_secret_version" "wordpress_keys" {
  secret_id = aws_secretsmanager_secret.wordpress_keys.id
  secret_string_wo = jsonencode({
    for name in local.wordpress_key_names : name => ephemeral.random_password.wordpress_keys[name].result
  })
  secret_string_wo_version = 1
}

# The latest Amazon Linux 2023 AMI for x86_64, from the public SSM parameter
# where AWS publishes it. Each new AMI makes a new launch template version,
# which the Auto Scaling group rolls out. Set var.ami_id to pin one AMI.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "this" {
  name          = "${var.name_prefix}-app-lt"
  image_id      = coalesce(var.ami_id, data.aws_ssm_parameter.al2023.insecure_value)
  instance_type = var.instance_type
  # No key pair: Session Manager replaces SSH.

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # The app subnets are private: no public IP, and only the app security
  # group, which lets in HTTP from the ALB alone.
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.app_sg_id]
    delete_on_termination       = true
  }

  # IMDSv2 only. A hop limit of 1 stops metadata responses at the Docker
  # bridge, so the WordPress container cannot take the instance role's
  # credentials. Amazon Linux 2023 sets 2 by default, for containers.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Amazon Linux 2023's root device. Its AMI is 8 GB and unencrypted; 20 GB
  # leaves room for the WordPress image, logs and uploads.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # No secrets in user_data: only the ARNs of the two secrets, which the
  # instances read at boot.
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region          = data.aws_region.current.region
    db_secret_arn   = var.db_secret_arn
    keys_secret_arn = aws_secretsmanager_secret.wordpress_keys.arn
    key_names       = local.wordpress_key_names
    db_address      = var.db_address
    db_port         = var.db_port
    db_name         = var.db_name
    domain_name     = var.domain_name
    wordpress_image = var.wordpress_image
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.instance_tags
  }

  tags = {
    Name = "${var.name_prefix}-app-lt"
  }
}

# The WordPress instances, spread over both app subnets. desired_capacity is
# left out on purpose: the scaling policies change it, and a value here would
# make every apply undo their work.
resource "aws_autoscaling_group" "this" {
  name                = "${var.name_prefix}-app-asg"
  vpc_zone_identifier = var.app_subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size

  # The ALB sends requests only to healthy instances, and the group replaces
  # any instance that fails the ALB's health check. The grace period gives a
  # new instance 300 seconds to install Docker and start WordPress first.
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  # The version number, not "$Latest": a new launch template version (a new
  # AMI, image tag or user_data) then changes the group, which starts the
  # instance refresh below.
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # Replaces every instance after a launch template change. New instances are
  # launched and healthy before old ones are terminated, so capacity never
  # drops.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
    }
  }

  # The provider's default tags do not apply to Auto Scaling groups. The
  # launch template already tags the instances, so these stay on the group.
  dynamic "tag" {
    for_each = merge(data.aws_default_tags.current.tags, {
      Name = "${var.name_prefix}-app-asg"
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# Simple scaling, one instance at a time. Target tracking aims at one CPU
# value, so it cannot express separate thresholds to scale out and in. After
# each change, the group waits out the 300-second cooldown before the next.
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.name_prefix}-app-scale-out"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.name_prefix}-app-scale-in"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# Average CPU across the group's instances, in 6 periods of 300 seconds:
# 6 x 300 s = 30 minutes, and all 6 must breach. EC2 basic monitoring
# publishes CPU every 5 minutes, so a shorter period would have no data.
# While an alarm stays in ALARM, it calls its policy again every minute, so
# the group keeps changing, one instance per cooldown, until the CPU is back
# in range or the group reaches max_size or min_size.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name        = "${var.name_prefix}-app-cpu-high"
  alarm_description = "Average CPU of the WordPress instances above ${var.scale_out_cpu_threshold}% for 30 minutes: add an instance."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.scale_out_cpu_threshold
  period              = 300
  evaluation_periods  = 6
  datapoints_to_alarm = 6

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name        = "${var.name_prefix}-app-cpu-low"
  alarm_description = "Average CPU of the WordPress instances below ${var.scale_in_cpu_threshold}% for 30 minutes: remove an instance."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  comparison_operator = "LessThanThreshold"
  threshold           = var.scale_in_cpu_threshold
  period              = 300
  evaluation_periods  = 6
  datapoints_to_alarm = 6

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}
