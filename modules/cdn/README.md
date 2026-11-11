# cdn module

The CloudFront distribution in front of the Web School WordPress stack, and the apex and www records that point at it. Visitors only ever reach CloudFront; CloudFront reaches the ALB.

- One distribution for the apex and www, with the site's certificate from us-east-1 (SNI) and the `TLSv1.2_2021` security policy: TLS 1.3 and 1.2 only. It keeps the ChaCha20 ciphers, which are faster than AES on phones without AES hardware. Plain HTTP is redirected to HTTPS.
- IPv6, HTTP/2 and HTTP/3 for visitors, and `PriceClass_200`, which includes the edge locations in Asia and leaves out the most expensive regions.
- One origin, the ALB, by its origin name (`origin_fqdn`), which the ALB's certificate covers: HTTPS only, TLS 1.2 or newer. Every request to it carries the `X-Origin-Verify` header with the origin secret. The ALB's security group admits every CloudFront distribution, so the secret is what tells ours apart.
- Pages are not cached, because they change for logged-in users, and allow every method, for logins, comments and the admin. They get the viewer's headers, cookies and query strings, but not the Host header: the ALB's certificate and WordPress's settings expect the origin name (`Managed-CachingDisabled` and `Managed-AllViewerExceptHostHeader`).
- `/wp-content/*` and `/wp-includes/*`, the theme, plugin, core and media files, are cached at the edge for 24 hours by default and compressed, with only GET and HEAD. Their cache policy, `<name_prefix>-static-files`, has the settings of AWS's managed `CachingOptimized` plus the `ver` query string in the cache key. WordPress adds `?ver=<version>` to the CSS and JavaScript it loads, so a new version gets a new URL, both at the edge and in browsers, which keep these files as long as they guess, because Apache in the image sends no cache headers. No other query string is in the key, so extra parameters cannot bypass the cache.
- Every response gets security headers (`Managed-SecurityHeadersPolicy`): `Strict-Transport-Security` for a year, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy` and `X-XSS-Protection`. Where WordPress sends one of these itself, its value wins, except for `X-Content-Type-Options`.
- A and AAAA alias records for the apex and www, with `evaluate_target_health = false`: Route 53 rejects `true` for an alias to CloudFront, and only when it creates the record. The alias zone comes from the distribution, not a hard-coded ID.
- Page requests for www get a permanent redirect (301) to the same path and query on the apex, from a CloudFront Function that runs before CloudFront looks at its cache. WordPress builds its links, fonts and scripts on the apex (`WP_HOME`), so on www, browsers would treat those as another site and block the fonts and the module scripts of interactive blocks, such as the mobile menu: Apache sends no CORS headers. The function gets the domain from Terraform, not from the request, so it cannot redirect anywhere else. `tests/functions/www_redirect.test.cjs` runs it with Node: `node --test "tests/functions/*.test.cjs"`.
- Not built: AWS WAF and its managed rules (checkov CKV_AWS_68, CKV2_AWS_47), access logs (CKV_AWS_86), a second origin to fail over to (CKV_AWS_310), and geo restriction (CKV_AWS_374), which would also block parents and alumni abroad. A default root object (CKV_AWS_305) does not apply: WordPress serves `/` itself.

## Files without ?ver=

Files that WordPress links without `?ver=`, such as uploads replaced under the same name or images and fonts that a stylesheet names, stay cached at the edge for up to 24 hours after they change. To clear them sooner, from the repository root:

```bash
aws cloudfront create-invalidation --distribution-id "$(terraform output -raw cloudfront_distribution_id)" --paths "/wp-content/*" "/wp-includes/*"
```

## Usage

```hcl
module "cdn" {
  source = "./modules/cdn"

  name_prefix                = "web-school-prod"
  domain_name                = "webschool.example"
  origin_fqdn                = module.alb.origin_fqdn
  cloudfront_certificate_arn = module.dns.cloudfront_certificate_arn
  zone_id                    = module.dns.zone_id
  origin_verify_secret       = random_password.origin_verify.result
}
```

The reference below is generated with `terraform-docs markdown table --output-file README.md --output-mode inject modules/cdn`.

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
| [aws_cloudfront_cache_policy.static](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_cache_policy) | resource |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.www_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_route53_record.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_cloudfront_cache_policy.caching_disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_origin_request_policy.all_viewer_except_host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_origin_request_policy) | data source |
| [aws_cloudfront_response_headers_policy.security_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_response_headers_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudfront_certificate_arn"></a> [cloudfront\_certificate\_arn](#input\_cloudfront\_certificate\_arn) | ARN of the validated ACM certificate for the apex and www. CloudFront accepts only certificates from us-east-1. | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name of the site, such as webschool.example. CloudFront serves it and its www name. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for resource names, such as web-school-prod. | `string` | n/a | yes |
| <a name="input_origin_fqdn"></a> [origin\_fqdn](#input\_origin\_fqdn) | Origin name that CloudFront connects to, such as origin.webschool.example. The ALB's certificate covers it. | `string` | n/a | yes |
| <a name="input_origin_verify_secret"></a> [origin\_verify\_secret](#input\_origin\_verify\_secret) | Secret that CloudFront sends to the ALB in the X-Origin-Verify header. The ALB forwards only requests that carry it. | `string` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the public hosted zone that gets the apex and www records. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudfront_domain_name"></a> [cloudfront\_domain\_name](#output\_cloudfront\_domain\_name) | Domain name that CloudFront gave the distribution, such as d111111abcdef8.cloudfront.net. The apex and www records point at it. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution, for cache invalidations. |
<!-- END_TF_DOCS -->
