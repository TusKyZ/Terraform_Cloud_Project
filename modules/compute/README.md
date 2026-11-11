# compute module

The WordPress servers for the Web School stack: an Auto Scaling group of Amazon Linux 2023 instances in the app subnets, each running the official WordPress Docker image behind the ALB.

- An instance role with AWS's managed Session Manager policy, which replaces SSH, and read access to exactly two secrets: the database credentials that RDS manages and the WordPress keys. The instances have no key pair.
- A secret with WordPress's eight authentication keys and salts, which must be the same on every instance. Terraform generates them as ephemeral values and stores them through a write-only argument, so they never reach the plan or the state. To replace them, which logs every user out, raise `secret_string_wo_version`.
- A launch template: the latest Amazon Linux 2023 AMI from AWS's public SSM parameter (or `ami_id`), t3.small, no public IP, only the app security group, and an encrypted 20 GB gp3 root volume. IMDSv2 is required with a hop limit of 1, so the container cannot reach the instance role's credentials. It tags the instances and their volumes, because the provider's default tags do not reach what an Auto Scaling group launches.
- user_data installs Docker and has systemd run WordPress in a container, from an image with a full version tag such as `7.1.3-php8.3-apache`:
  - A script copies the database credentials and the keys from Secrets Manager into files in `/run/wordpress`, which is in memory and readable only by the container's web server user. A systemd timer runs it every minute, so the password that RDS rotates every week reaches WordPress within a minute, without a restart. It checks every value before it replaces any file, so a failed fetch, or a missing, null or empty value, leaves the old files in place.
  - The container mounts that folder read-only, and the image's `wp-config.php` reads each value from its file (the `*_FILE` settings) on every request. No secret is in user_data, on a command line or in the container's environment.
  - WordPress connects to the database over TLS (`MYSQL_CLIENT_FLAGS`). It does not check the database's certificate: WordPress has no setting for a database CA.
  - `WP_HOME` and `WP_SITEURL` are `https://<domain_name>`, because WordPress sees the Host `origin.<domain_name>`.
  - `DISALLOW_FILE_MODS` and `AUTOMATIC_UPDATER_DISABLED` stop WordPress installing plugins, themes or updates by itself: each instance has its own copy, so such a change would reach one instance only. New code, security fixes included, comes with a new image tag. A stolen admin login also cannot upload PHP through the plugin installer.
- An Auto Scaling group of 1 to 4 instances over both app subnets, registered in the ALB's target group. It replaces any instance that fails the ALB's health check, after a 300-second grace period. A new launch template version (a new AMI, image tag or user_data) rolls out through an instance refresh that launches new instances before it terminates old ones.
- Scaling on the group's average CPU: above 80% for 30 minutes adds an instance, and below 40% for 30 minutes removes one (6 periods of 300 seconds, because EC2 basic monitoring publishes every 5 minutes). Simple scaling policies with a 300-second cooldown, because target tracking cannot use two thresholds.
- Not built: shared storage for uploads (EFS or S3), so uploads stay on each instance's disk; automatic rotation of the WordPress keys, which would need a Lambda function and would log every user out (checkov CKV2_AWS_57); and a customer-managed KMS key for the keys secret, which the AWS managed key already encrypts (checkov CKV_AWS_149).

## Usage

```hcl
module "compute" {
  source = "./modules/compute"

  name_prefix      = "web-school-prod"
  app_subnet_ids   = module.network.app_subnet_ids
  app_sg_id        = module.security.app_sg_id
  target_group_arn = module.alb.target_group_arn
  db_address       = module.database.db_address
  db_port          = module.database.db_port
  db_name          = module.database.db_name
  db_secret_arn    = module.database.db_secret_arn
  domain_name      = "webschool.example"
  wordpress_image  = "public.ecr.aws/docker/library/wordpress:7.1.3-php8.3-apache"
}
```

`public.ecr.aws/docker/library/wordpress` is Docker's official WordPress image, mirrored on Amazon ECR Public with the same image digest. Pulls from EC2 avoid Docker Hub's limit of 100 anonymous pulls per 6 hours, which all instances behind one NAT gateway would share.

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/compute`. terraform-docs does not list ephemeral resources: the module also uses `random_password` from the hashicorp/random provider, as the ephemeral resource that generates the WordPress keys.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.7 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_policy.scale_in](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_autoscaling_policy.scale_out](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_cloudwatch_metric_alarm.cpu_high](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.cpu_low](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_instance_profile.instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.read_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_secretsmanager_secret.wordpress_keys](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.wordpress_keys](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_default_tags.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |
| [aws_iam_policy.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI for the instances. Leave null to use the latest Amazon Linux 2023 for x86\_64, or set it to pin one AMI. It must be an Amazon Linux 2023 AMI: user\_data uses dnf, and the launch template sets up its root device, /dev/xvda. | `string` | `null` | no |
| <a name="input_app_sg_id"></a> [app\_sg\_id](#input\_app\_sg\_id) | ID of the app security group, which allows HTTP only from the ALB. | `string` | n/a | yes |
| <a name="input_app_subnet_ids"></a> [app\_subnet\_ids](#input\_app\_subnet\_ids) | IDs of the app subnets, one per AZ. The Auto Scaling group spreads the instances over them. | `list(string)` | n/a | yes |
| <a name="input_db_address"></a> [db\_address](#input\_db\_address) | Host name of the database. | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Name of the WordPress database. | `string` | n/a | yes |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | Port the database listens on. | `number` | n/a | yes |
| <a name="input_db_secret_arn"></a> [db\_secret\_arn](#input\_db\_secret\_arn) | ARN of the Secrets Manager secret where RDS keeps the master user's credentials. The instances read the database user name and password from it. | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name of the site, such as webschool.example. WordPress builds its links from https://webschool.example in that case. | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for the WordPress instances. | `string` | `"t3.small"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Largest number of instances the Auto Scaling group may run. | `number` | `4` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Smallest number of instances the Auto Scaling group keeps running. | `number` | `1` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_scale_in_cpu_threshold"></a> [scale\_in\_cpu\_threshold](#input\_scale\_in\_cpu\_threshold) | Average CPU percentage of the group below which, for 30 minutes, the group removes an instance. | `number` | `40` | no |
| <a name="input_scale_out_cpu_threshold"></a> [scale\_out\_cpu\_threshold](#input\_scale\_out\_cpu\_threshold) | Average CPU percentage of the group above which, for 30 minutes, the group adds an instance. | `number` | `80` | no |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | ARN of the ALB's target group. The Auto Scaling group registers its instances in it. | `string` | n/a | yes |
| <a name="input_wordpress_image"></a> [wordpress\_image](#input\_wordpress\_image) | The official WordPress image, Apache variant, with a full version tag, such as public.ecr.aws/docker/library/wordpress:7.1.3-php8.3-apache. A new tag makes a new launch template version, which the Auto Scaling group rolls out. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Name of the Auto Scaling group that runs the WordPress instances. |
| <a name="output_instance_role_arn"></a> [instance\_role\_arn](#output\_instance\_role\_arn) | ARN of the IAM role that the WordPress instances run as. |
<!-- END_TF_DOCS -->
