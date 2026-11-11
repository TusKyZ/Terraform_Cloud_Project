# Unit tests for modules/cdn. They plan against a mock AWS provider, so they
# need no AWS credentials and create nothing.

mock_provider "aws" {}

# The real ID of AWS's managed security headers policy, in place of the
# mock's random string. The provider declares the id of the cache policy and
# origin request policy data sources as an input, so the mock leaves those
# null and an override cannot set them; the real plan shows their IDs.
override_data {
  target = data.aws_cloudfront_response_headers_policy.security_headers
  values = {
    id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }
}

variables {
  name_prefix                = "web-school-prod"
  domain_name                = "webschool.example"
  origin_fqdn                = "origin.webschool.example"
  cloudfront_certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test"
  origin_verify_secret       = "FakeTestSecret0123456789abcdefgh"
  zone_id                    = "Z0TEST"
}

run "distribution_serves_the_apex_and_www" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["webschool.example", "www.webschool.example"])
    error_message = "The distribution must serve the apex and www."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.enabled == true &&
      aws_cloudfront_distribution.this.is_ipv6_enabled == true
    )
    error_message = "The distribution must be enabled and answer over IPv6 too."
  }

  # PriceClass_200 includes the edge locations in Asia, where the schools'
  # visitors are, and leaves out only the most expensive regions.
  assert {
    condition = (
      aws_cloudfront_distribution.this.price_class == "PriceClass_200" &&
      aws_cloudfront_distribution.this.http_version == "http2and3"
    )
    error_message = "The distribution must use PriceClass_200 and allow HTTP/2 and HTTP/3."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Name"] == "web-school-prod-cdn"
    error_message = "The distribution's Name tag must be <name_prefix>-cdn."
  }
}

run "viewers_get_https_with_tls_1_2_or_newer" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:111122223333:certificate/cloudfront-test" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    )
    error_message = "Viewers must get the site's own certificate, by SNI, with TLS 1.2 or newer."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Plain HTTP requests must be redirected to HTTPS."
  }
}

# CloudFront connects by the origin name, which the ALB's certificate covers.
run "origin_is_the_alb_over_https_only" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this.origin) == 1 &&
      one(aws_cloudfront_distribution.this.origin).domain_name == "origin.webschool.example"
    )
    error_message = "The only origin must be the ALB, by its origin name."
  }

  assert {
    condition = (
      one(aws_cloudfront_distribution.this.origin).custom_origin_config[0].origin_protocol_policy == "https-only" &&
      one(aws_cloudfront_distribution.this.origin).custom_origin_config[0].https_port == 443 &&
      one(aws_cloudfront_distribution.this.origin).custom_origin_config[0].origin_ssl_protocols == toset(["TLSv1.2"])
    )
    error_message = "CloudFront must reach the ALB over HTTPS only, on port 443, with TLS 1.2 or newer."
  }
}

# The ALB forwards only requests that carry this header with the secret.
run "every_origin_request_carries_the_secret_header" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition = one(one(aws_cloudfront_distribution.this.origin).custom_header) == {
      name  = "X-Origin-Verify"
      value = "FakeTestSecret0123456789abcdefgh"
    }
    error_message = "Every request to the origin must carry the X-Origin-Verify header with the secret."
  }
}

# WordPress pages are personal once someone logs in, so they are not cached.
# The viewer's Host header stays out: the ALB's certificate and WordPress's
# settings expect the origin name.
run "pages_are_not_cached_and_the_host_header_is_not_forwarded" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition = (
      data.aws_cloudfront_cache_policy.caching_disabled.name == "Managed-CachingDisabled" &&
      data.aws_cloudfront_origin_request_policy.all_viewer_except_host.name == "Managed-AllViewerExceptHostHeader"
    )
    error_message = "The module must look up AWS's managed CachingDisabled and AllViewerExceptHostHeader policies."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == data.aws_cloudfront_cache_policy.caching_disabled.id &&
      aws_cloudfront_distribution.this.default_cache_behavior[0].origin_request_policy_id == data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    )
    error_message = "The default behaviour must not cache, and must forward everything but the Host header."
  }

  # Logins, comments and the admin need every method.
  assert {
    condition = (
      aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods == toset(["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]) &&
      aws_cloudfront_distribution.this.default_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    )
    error_message = "The default behaviour must allow all methods."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].target_origin_id == one(aws_cloudfront_distribution.this.origin).origin_id
    error_message = "The default behaviour must send requests to the ALB."
  }
}

run "responses_get_security_headers" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition     = data.aws_cloudfront_response_headers_policy.security_headers.name == "Managed-SecurityHeadersPolicy"
    error_message = "The module must look up AWS's managed SecurityHeadersPolicy."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    error_message = "Pages must get the security headers, such as HSTS."
  }
}

# Theme, plugin and core files change only with a new image, so the edge
# caches them. The viewer's Host header stays out, as for pages.
run "static_files_are_cached_at_the_edge" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  # A fixed fake ID, so the behaviours' cache policy can be checked.
  override_resource {
    target          = aws_cloudfront_cache_policy.static
    override_during = plan
    values = {
      id = "static-files-test"
    }
  }

  assert {
    condition     = [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.path_pattern] == ["/wp-content/*", "/wp-includes/*"]
    error_message = "Only /wp-content/* and /wp-includes/* may get their own cache behaviours."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.cache_policy_id == "static-files-test" &&
      b.origin_request_policy_id == null &&
      b.target_origin_id == one(aws_cloudfront_distribution.this.origin).origin_id
    ])
    error_message = "Static files must use the static files cache policy, go to the ALB, and get no other viewer values."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.allowed_methods == toset(["GET", "HEAD"]) && b.cached_methods == toset(["GET", "HEAD"])
    ])
    error_message = "Static files must allow only GET and HEAD."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.viewer_protocol_policy == "redirect-to-https" &&
      b.compress == true &&
      b.response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    ])
    error_message = "Static files must be served over HTTPS, compressed, with the security headers."
  }
}

# WordPress adds ?ver=<version> to the CSS and JavaScript it loads. With ver
# in the cache key, a new version gets a new URL at the edge and in browsers.
# Only ver: any other query string would let random parameters bypass the
# cache.
run "static_files_cache_key_includes_only_the_ver_query_string" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition = (
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].query_strings_config[0].query_string_behavior == "whitelist" &&
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].query_strings_config[0].query_strings[0].items == toset(["ver"])
    )
    error_message = "The static files cache key must include the ver query string and no other."
  }

  # The rest matches AWS's managed CachingOptimized policy.
  assert {
    condition = (
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].cookies_config[0].cookie_behavior == "none" &&
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].headers_config[0].header_behavior == "none" &&
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].enable_accept_encoding_gzip == true &&
      aws_cloudfront_cache_policy.static.parameters_in_cache_key_and_forwarded_to_origin[0].enable_accept_encoding_brotli == true
    )
    error_message = "The static files cache key must leave out cookies and headers, and keep gzip and Brotli copies apart."
  }

  assert {
    condition = (
      aws_cloudfront_cache_policy.static.min_ttl == 1 &&
      aws_cloudfront_cache_policy.static.default_ttl == 86400 &&
      aws_cloudfront_cache_policy.static.max_ttl == 31536000
    )
    error_message = "Static files must stay cached for 24 hours by default, as with CachingOptimized."
  }

  assert {
    condition     = aws_cloudfront_cache_policy.static.name == "web-school-prod-static-files"
    error_message = "The cache policy's name must be <name_prefix>-static-files."
  }
}

# The apex and www, each with an A record for IPv4 and an AAAA record for
# IPv6, all aliases to the distribution.
run "apex_and_www_point_at_cloudfront" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  # Fixed fake values for what CloudFront only knows once the distribution
  # exists.
  override_resource {
    target          = aws_cloudfront_distribution.this
    override_during = plan
    values = {
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z0CLOUDFRONT"
    }
  }

  assert {
    condition = sort([for r in aws_route53_record.site : "${r.name} ${r.type}"]) == tolist([
      "webschool.example A",
      "webschool.example AAAA",
      "www.webschool.example A",
      "www.webschool.example AAAA",
    ])
    error_message = "The apex and www must each get an A and an AAAA record."
  }

  assert {
    condition     = toset([for r in aws_route53_record.site : r.name]) == aws_cloudfront_distribution.this.aliases
    error_message = "The records must be for the names the distribution serves."
  }

  # The alias zone comes from the distribution, not a hard-coded ID.
  assert {
    condition = alltrue([
      for r in aws_route53_record.site :
      r.zone_id == "Z0TEST" &&
      length(r.alias) == 1 &&
      r.alias[0].name == "d111111abcdef8.cloudfront.net" &&
      r.alias[0].zone_id == "Z0CLOUDFRONT"
    ])
    error_message = "Every record must be an alias to the distribution, in the site's hosted zone."
  }
}

# Route 53 rejects true for an alias to CloudFront, and only when it creates
# the record, so a plan would not show the mistake.
run "cloudfront_aliases_do_not_evaluate_target_health" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.site : r.alias[0].evaluate_target_health == false])
    error_message = "Every alias to CloudFront must set evaluate_target_health = false."
  }
}

# WordPress builds its links, fonts and scripts on the apex. On www, browsers
# would treat those as another site and block the fonts and the module
# scripts of interactive blocks, such as the mobile menu. A CloudFront
# Function sends page requests for www to the apex. tests/functions checks
# what the function does; this run checks how the module wires it.
run "www_page_requests_are_redirected_to_the_apex" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  override_resource {
    target          = aws_cloudfront_function.www_redirect
    override_during = plan
    values = {
      arn = "arn:aws:cloudfront::111122223333:function/web-school-prod-www-redirect"
    }
  }

  assert {
    condition = aws_cloudfront_distribution.this.default_cache_behavior[0].function_association == toset([{
      event_type   = "viewer-request"
      function_arn = "arn:aws:cloudfront::111122223333:function/web-school-prod-www-redirect"
    }])
    error_message = "Page requests must go through the www redirect before CloudFront looks at the cache."
  }

  # WordPress never links static files through www.
  assert {
    condition     = alltrue([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : length(b.function_association) == 0])
    error_message = "Static files need no redirect."
  }

  assert {
    condition = (
      aws_cloudfront_function.www_redirect.runtime == "cloudfront-js-2.0" &&
      aws_cloudfront_function.www_redirect.publish == true &&
      aws_cloudfront_function.www_redirect.name == "web-school-prod-www-redirect"
    )
    error_message = "The function must be published on the cloudfront-js-2.0 runtime, named <name_prefix>-www-redirect."
  }

  # The function gets the domain from Terraform, not from the request, so it
  # cannot redirect anywhere else.
  assert {
    condition = (
      strcontains(aws_cloudfront_function.www_redirect.code, "!== 'www.webschool.example'") &&
      strcontains(aws_cloudfront_function.www_redirect.code, "'https://webschool.example' + request.uri") &&
      strcontains(aws_cloudfront_function.www_redirect.code, "statusCode: 301")
    )
    error_message = "The function must send www.<domain_name> to https://<domain_name> with a 301."
  }
}

run "outputs_are_the_distribution_id_and_domain_name" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  # Fixed fake values for what CloudFront only knows once the distribution
  # exists.
  override_resource {
    target          = aws_cloudfront_distribution.this
    override_during = plan
    values = {
      id          = "EDFDVBD6EXAMPLE"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }

  assert {
    condition = (
      output.distribution_id == "EDFDVBD6EXAMPLE" &&
      output.cloudfront_domain_name == "d111111abcdef8.cloudfront.net"
    )
    error_message = "The outputs must be the distribution's ID and its CloudFront domain name."
  }
}

# CloudFront accepts only certificates from us-east-1.
run "certificate_outside_us_east_1_is_rejected" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  variables {
    cloudfront_certificate_arn = "arn:aws:acm:ap-southeast-3:111122223333:certificate/alb-test"
  }

  expect_failures = [var.cloudfront_certificate_arn]
}

# The ALB treats * and ? in header values as wildcards, so the secret must be
# letters and digits only.
run "origin_secret_with_wildcards_is_rejected" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  variables {
    origin_verify_secret = "FakeTestSecret0123456789abcdef*?"
  }

  expect_failures = [var.origin_verify_secret]
}

run "short_origin_secret_is_rejected" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  variables {
    origin_verify_secret = "FakeTestSecret"
  }

  expect_failures = [var.origin_verify_secret]
}

# The function's code holds the domain between quotes, so a quote in the name
# would change the code. The rule is the dns module's.
run "domain_name_with_a_quote_is_rejected" {
  command = plan

  module {
    source = "./modules/cdn"
  }

  variables {
    domain_name = "webschool.example'"
  }

  expect_failures = [var.domain_name]
}
