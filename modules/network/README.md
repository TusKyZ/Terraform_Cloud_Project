# network module

The network for the Web School WordPress stack: one VPC in one Region, spread over two or more Availability Zones (AZs).

- A VPC with DNS support and DNS hostnames turned on, so instances can resolve AWS names such as the RDS endpoint.
- In each AZ, a public subnet (ALB and NAT gateway), an app subnet (WordPress instances) and a DB subnet (RDS). Subnets are keyed by AZ name, and none gives instances a public IP.
- An internet gateway, and one NAT gateway with its own Elastic IP in each AZ's public subnet.
- Route tables: the public subnets send `0.0.0.0/0` to the internet gateway, each app subnet sends it to the NAT gateway in its own AZ, and the DB subnets get only the local route.
- The VPC's default security group and default network ACL, taken over with every rule removed, so anything launched without a security group, or any subnet left on the default network ACL, gets no traffic.

Every list input takes one item per AZ, in the same order as `azs`, and every list output follows that order.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  name_prefix         = "web-school-prod"
  vpc_cidr            = "10.0.0.0/16"
  azs                 = ["ap-southeast-3a", "ap-southeast-3b"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
  db_subnet_cidrs     = ["10.0.21.0/24", "10.0.22.0/24"]
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/network`.

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
| [aws_default_network_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_subnet_cidrs"></a> [app\_subnet\_cidrs](#input\_app\_subnet\_cidrs) | IPv4 CIDR blocks for the app subnets (WordPress instances), one per AZ in the same order as azs. | `list(string)` | n/a | yes |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability Zones to use, at least two, such as ["ap-southeast-3a", "ap-southeast-3b"]. | `list(string)` | n/a | yes |
| <a name="input_db_subnet_cidrs"></a> [db\_subnet\_cidrs](#input\_db\_subnet\_cidrs) | IPv4 CIDR blocks for the DB subnets (RDS), one per AZ in the same order as azs. | `list(string)` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | IPv4 CIDR blocks for the public subnets (ALB and NAT gateways), one per AZ in the same order as azs. | `list(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR block for the VPC, such as 10.0.0.0/16. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_subnet_cidrs"></a> [app\_subnet\_cidrs](#output\_app\_subnet\_cidrs) | IPv4 CIDR blocks of the app subnets, in the same order as azs. |
| <a name="output_app_subnet_ids"></a> [app\_subnet\_ids](#output\_app\_subnet\_ids) | IDs of the app subnets (WordPress instances), in the same order as azs. |
| <a name="output_db_subnet_cidrs"></a> [db\_subnet\_cidrs](#output\_db\_subnet\_cidrs) | IPv4 CIDR blocks of the DB subnets, in the same order as azs. |
| <a name="output_db_subnet_ids"></a> [db\_subnet\_ids](#output\_db\_subnet\_ids) | IDs of the DB subnets (RDS), in the same order as azs. |
| <a name="output_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#output\_public\_subnet\_cidrs) | IPv4 CIDR blocks of the public subnets, in the same order as azs. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | IDs of the public subnets (ALB and NAT gateways), in the same order as azs. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
<!-- END_TF_DOCS -->
