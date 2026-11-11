# security module

The security groups and network ACLs for the Web School WordPress stack. Security groups are stateful and filter traffic for each resource: the reply to an allowed connection is let back in automatically. Network ACLs are stateless and filter traffic for each subnet tier, so every allowed flow also needs a rule for its replies, which go to ports 1024-65535.

| Layer | Inbound | Outbound |
|---|---|---|
| ALB security group | 443 from CloudFront's origin-facing prefix list | 80 to the app security group |
| App security group | 80 from the ALB security group | 3306 to the DB security group; 443 to anywhere, through the NAT gateways |
| DB security group | 3306 from the app security group | none |
| Public network ACL | 443 and 1024-65535 from anywhere | 80 to the app subnets; 443 and 1024-65535 to anywhere |
| App network ACL | 80 from the public subnets; 1024-65535 from anywhere | 3306 to the DB subnets; 443 to anywhere; 1024-65535 to the public subnets |
| DB network ACL | 3306 from the app subnets | 1024-65535 to the app subnets |

- Security groups use a name prefix and `create_before_destroy`, so a replacement group is created before the old one is deleted.
- Network ACL rules are inline, so Terraform removes any rule added by hand. A rule that covers a tier gets one entry per subnet CIDR block.

## Usage

```hcl
module "security" {
  source = "./modules/security"

  name_prefix         = "web-school-prod"
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  app_subnet_ids      = module.network.app_subnet_ids
  db_subnet_ids       = module.network.db_subnet_ids
  public_subnet_cidrs = module.network.public_subnet_cidrs
  app_subnet_cidrs    = module.network.app_subnet_cidrs
  db_subnet_cidrs     = module.network.db_subnet_cidrs
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/security`.

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
| [aws_network_acl.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_http_to_app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.app_https_to_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.app_mysql_to_db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_https_from_cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.app_http_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.db_mysql_from_app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ec2_managed_prefix_list.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_subnet_cidrs"></a> [app\_subnet\_cidrs](#input\_app\_subnet\_cidrs) | IPv4 CIDR blocks of the app subnets, used in the network ACL rules. | `list(string)` | n/a | yes |
| <a name="input_app_subnet_ids"></a> [app\_subnet\_ids](#input\_app\_subnet\_ids) | IDs of the app subnets, which get the app network ACL. | `list(string)` | n/a | yes |
| <a name="input_db_subnet_cidrs"></a> [db\_subnet\_cidrs](#input\_db\_subnet\_cidrs) | IPv4 CIDR blocks of the DB subnets, used in the network ACL rules. | `list(string)` | n/a | yes |
| <a name="input_db_subnet_ids"></a> [db\_subnet\_ids](#input\_db\_subnet\_ids) | IDs of the DB subnets, which get the DB network ACL. | `list(string)` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | IPv4 CIDR blocks of the public subnets, used in the network ACL rules. | `list(string)` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | IDs of the public subnets, which get the public network ACL. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC that the security groups and network ACLs belong to. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_sg_id"></a> [alb\_sg\_id](#output\_alb\_sg\_id) | ID of the ALB security group. |
| <a name="output_app_sg_id"></a> [app\_sg\_id](#output\_app\_sg\_id) | ID of the app security group, for the WordPress instances. |
| <a name="output_db_sg_id"></a> [db\_sg\_id](#output\_db\_sg\_id) | ID of the DB security group, for RDS. |
<!-- END_TF_DOCS -->
