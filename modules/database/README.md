# database module

The MySQL database for the Web School WordPress stack: one RDS instance with a standby in a second AZ, reachable only from the app instances.

- A DB subnet group over the DB subnets, which have no route to the internet.
- RDS for MySQL 8.4 on db.t3.micro. MySQL 8.0 left RDS standard support on 31 July 2026, and 8.4 has it until 31 July 2029. RDS picks the minor version and applies minor upgrades itself.
- Multi-AZ: a standby in the other AZ takes over if the primary or its AZ fails.
- Not publicly accessible. The only way in is the DB security group, which allows MySQL from the app security group.
- Every connection must use TLS: a parameter group turns on `require_secure_transport`, which RDS for MySQL leaves off by default. WordPress connects with TLS, set by the compute module.
- Encrypted gp3 storage, starting at 20 GB (the gp3 minimum) and growing on its own up to 100 GB.
- RDS creates the master password, keeps it in Secrets Manager and rotates it, so it is never in the code or the Terraform state. The module moves the weekly rotation to Sunday between 02:00 and 04:00 Jakarta time (UTC+7), when school sites are quiet. The instances read the password from the secret in `db_secret_arn` and pick up a new one within a minute.
- Automated backups kept for 7 days, with the database's tags copied to its snapshots.
- The MySQL error log goes to CloudWatch Logs, into `/aws/rds/instance/<identifier>/error`. The module creates that log group before the database, with 365-day retention, because a log group that RDS creates itself keeps logs forever.
- Deletion protection, and a final snapshot named `<name_prefix>-db-final` when the database is deleted. Turn both off only for a throwaway deploy.
- Not built: enhanced monitoring, a next step in the report; IAM database authentication, which WordPress cannot use; and a customer-managed KMS key for the log group, which CloudWatch Logs encrypts at rest anyway (checkov CKV_AWS_118, CKV_AWS_161 and CKV_AWS_158). Performance Insights is not offered for MySQL on db.t3.micro.

## Usage

```hcl
module "database" {
  source = "./modules/database"

  name_prefix         = "web-school-prod"
  db_subnet_ids       = module.network.db_subnet_ids
  db_sg_id            = module.security.db_sg_id
  deletion_protection = true
  skip_final_snapshot = false
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/database`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.error](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_secretsmanager_secret_rotation.master_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_db_sg_id"></a> [db\_sg\_id](#input\_db\_sg\_id) | ID of the DB security group, which allows MySQL only from the app instances. | `string` | n/a | yes |
| <a name="input_db_subnet_ids"></a> [db\_subnet\_ids](#input\_db\_subnet\_ids) | IDs of the DB subnets, one per AZ. RDS needs subnets in at least two AZs. | `list(string)` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether RDS refuses to delete the database. Set to false only for a throwaway deploy. | `bool` | `true` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Whether deleting the database skips the final snapshot. Set to true only for a throwaway deploy. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_address"></a> [db\_address](#output\_db\_address) | Host name of the database, for WordPress to connect to. |
| <a name="output_db_name"></a> [db\_name](#output\_db\_name) | Name of the WordPress database. |
| <a name="output_db_port"></a> [db\_port](#output\_db\_port) | Port the database listens on. |
| <a name="output_db_secret_arn"></a> [db\_secret\_arn](#output\_db\_secret\_arn) | ARN of the Secrets Manager secret where RDS keeps the master user's credentials. The instances read it at boot. |
<!-- END_TF_DOCS -->
