# alb module

The Application Load Balancer for the Web School WordPress stack. CloudFront is its only client: the ALB takes HTTPS from CloudFront and forwards plain HTTP to the WordPress instances inside the VPC.

- An internet-facing ALB in the public subnets, behind the ALB security group, which allows HTTPS only from CloudFront's origin-facing addresses. It drops headers that are not valid HTTP and has deletion protection on.
- One listener, HTTPS on port 443, with the certificate for the origin name and the `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` policy, AWS's current recommendation: TLS 1.3 and 1.2 only, with only AES-GCM ciphers for TLS 1.2. Its post-quantum key exchange goes unused, because CloudFront connects to origins with classical key exchange. There is no port 80 listener.
- One rule: a request whose `X-Origin-Verify` header carries the origin secret goes to the target group. Every other request gets a fixed 403 from the ALB. The security group alone is not enough, because every CloudFront distribution shares the same addresses. The secret is letters and digits only, because the ALB compares header values without regard to case and treats `*` and `?` as wildcards.
- A target group for the instances on HTTP port 80, with a health check on `/` that accepts 200-399, and 30 seconds of draining when an instance leaves.
- An alias record for `origin.<domain>`. CloudFront must connect by that name: the ALB's own DNS name is not on its certificate.
- TLS ends at the ALB, so traffic from the ALB to the instances is plain HTTP inside the VPC.
- Not built: access logs, AWS WAF and end-to-end TLS to the instances (checkov CKV_AWS_91 and CKV2_AWS_28), next steps in the report.

## Usage

```hcl
module "alb" {
  source = "./modules/alb"

  name_prefix          = "web-school-prod"
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  alb_sg_id            = module.security.alb_sg_id
  alb_certificate_arn  = module.dns.alb_certificate_arn
  zone_id              = module.dns.zone_id
  domain_name          = "webschool.example"
  origin_verify_secret = random_password.origin_verify.result
  deletion_protection  = true
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/alb`.

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
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.origin_verify](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_certificate_arn"></a> [alb\_certificate\_arn](#input\_alb\_certificate\_arn) | ARN of the validated ACM certificate for the origin name, for the HTTPS listener. | `string` | n/a | yes |
| <a name="input_alb_sg_id"></a> [alb\_sg\_id](#input\_alb\_sg\_id) | ID of the ALB security group, which allows HTTPS only from CloudFront. | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether AWS refuses to delete the ALB. Set to false only for a throwaway deploy. | `bool` | `true` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name of the site, such as webschool.example. The module points the origin name, origin.webschool.example in that case, at the ALB. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_origin_verify_secret"></a> [origin\_verify\_secret](#input\_origin\_verify\_secret) | Secret that CloudFront sends in the X-Origin-Verify header. The ALB forwards only requests that carry it. | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | IDs of the public subnets, one per AZ. An ALB needs subnets in at least two AZs. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC, for the target group. | `string` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the public hosted zone that gets the origin record. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. CloudFront does not use it: it connects through origin\_fqdn, which the ALB's certificate covers. |
| <a name="output_origin_fqdn"></a> [origin\_fqdn](#output\_origin\_fqdn) | Origin name that CloudFront connects to, such as origin.webschool.example. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ARN of the target group, for the Auto Scaling group to register the WordPress instances in. |
<!-- END_TF_DOCS -->
