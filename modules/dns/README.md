# dns module

DNS and TLS certificates for the Web School WordPress stack: the public Route 53 hosted zone for the site's domain, and the two ACM certificates that HTTPS needs, both validated through DNS records in that zone.

- A public hosted zone for `domain_name`. The cdn module adds the apex and `www` records to it, and the alb module adds `origin.<domain>`.
- A certificate for the apex and `www`, in us-east-1, because CloudFront only uses ACM certificates from that Region. This certificate and its validation are the only resources outside the provider's Region, and they set `region` themselves.
- A certificate for `origin.<domain>`, in the stack's Region, for the ALB. CloudFront connects to the ALB by that name, so the ALB's certificate must match it.
- One CNAME validation record per domain name, and a validation for each certificate that waits until ACM has issued it. The certificate ARN outputs come from the validations, so the ALB and CloudFront only ever get issued certificates.
- Both certificates use `create_before_destroy`, because ACM cannot delete a certificate that is still in use.
- Not built: DNSSEC signing and DNS query logging (checkov CKV2_AWS_38 and CKV2_AWS_39). The report lists them as next steps.

## First apply

ACM can only validate the certificates once the domain's registrar points the domain at this zone. On a first deploy:

1. Create the zone on its own: `terraform apply -target=module.dns.aws_route53_zone.this`. It ends by printing the zone's name servers as the root output `name_servers`.
2. At the registrar, set the domain's name servers to those. `terraform output name_servers` prints them again.
3. Run `terraform apply` for everything else. Each validation waits up to 75 minutes for ACM to issue its certificate.

## Usage

```hcl
module "dns" {
  source = "./modules/dns"

  name_prefix = "web-school-prod"
  domain_name = "webschool.example"
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/dns`.

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
| [aws_acm_certificate.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_acm_certificate_validation.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name of the site, such as webschool.example. The module creates a public hosted zone for it. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_certificate_arn"></a> [alb\_certificate\_arn](#output\_alb\_certificate\_arn) | ARN of the certificate for the origin name, such as origin.webschool.example, for the ALB's HTTPS listener. It comes from the validation, so anything that uses it waits until ACM has issued the certificate. |
| <a name="output_cloudfront_certificate_arn"></a> [cloudfront\_certificate\_arn](#output\_cloudfront\_certificate\_arn) | ARN of the us-east-1 certificate for the apex and www, for CloudFront. It comes from the validation, so anything that uses it waits until ACM has issued the certificate. |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | Name servers of the hosted zone. The domain's registrar must list them before ACM can validate the certificates. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | ID of the public hosted zone, for the site's DNS records. |
<!-- END_TF_DOCS -->
