locals {
  # The ALB, the distribution's only origin.
  origin_id = "alb"

  # The names the site answers to.
  site_names = {
    apex = var.domain_name
    www  = "www.${var.domain_name}"
  }
}

# AWS's managed policies, looked up by name.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Sends the origin every header but Host, and all cookies and query strings.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Adds Strict-Transport-Security, X-Content-Type-Options, X-Frame-Options,
# Referrer-Policy and X-XSS-Protection to every response, unless WordPress
# sent its own (X-Content-Type-Options always).
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

# For theme, plugin and core files: the settings of AWS's managed
# CachingOptimized policy (24 hours by default, gzip and Brotli copies kept
# apart), plus the ver query string in the cache key. WordPress adds
# ?ver=<version> to the CSS and JavaScript it loads, so a new version gets a
# new URL at the edge and in browsers. Apache in the image sends no cache
# headers, so browsers cache these files for as long as they guess. No other
# query string is in the key, so extra parameters cannot bypass the cache.
resource "aws_cloudfront_cache_policy" "static" {
  name    = "${var.name_prefix}-static-files"
  comment = "WordPress static files: CachingOptimized plus the ver query string"

  min_ttl     = 1
  default_ttl = 86400
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "whitelist"

      query_strings {
        items = ["ver"]
      }
    }
  }
}

# Sends page requests for www to the same path and query on the apex.
# WordPress builds its links, fonts and scripts on the apex, so on www,
# browsers would treat those as another site and block the fonts and the
# module scripts of interactive blocks, such as the mobile menu.
resource "aws_cloudfront_function" "www_redirect" {
  name    = "${var.name_prefix}-www-redirect"
  comment = "301 from www to the apex"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/templates/www_redirect.js.tftpl", {
    domain_name = var.domain_name
  })
}

resource "aws_cloudfront_distribution" "this" {
  # checkov:skip=CKV_AWS_305:Not applicable. The origin is WordPress, which serves / itself; a default root object is for static origins such as S3.
  comment = "${var.name_prefix} WordPress"
  enabled = true
  aliases = values(local.site_names)

  is_ipv6_enabled = true
  # HTTP/3 helps phones on unstable mobile networks; browsers without it use
  # HTTP/2.
  http_version = "http2and3"
  # Edge locations in Asia, where the schools' visitors are, without the most
  # expensive regions.
  price_class = "PriceClass_200"

  # CloudFront connects to the ALB by the origin name, which the ALB's
  # certificate covers, over HTTPS only.
  origin {
    origin_id   = local.origin_id
    domain_name = var.origin_fqdn

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # The ALB forwards only requests that carry this header. Its security
    # group admits every CloudFront distribution, so the secret is what tells
    # ours apart.
    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_secret
    }
  }

  # WordPress pages: not cached, because they change for logged-in users, and
  # all methods, for logins, comments and the admin. The viewer's Host header
  # stays out: the ALB's certificate and WordPress's settings expect the
  # origin name.
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    # Static files need no redirect: WordPress never links them through www.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.www_redirect.arn
    }
  }

  # Theme, plugin and core files, which change only with a new image, are
  # cached at the edge and compressed. They need nothing from the viewer but
  # the ver query string, which the cache policy sends, so there is no origin
  # request policy: CloudFront then sends the origin name as the Host.
  dynamic "ordered_cache_behavior" {
    for_each = ["/wp-content/*", "/wp-includes/*"]

    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = local.origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id            = aws_cloudfront_cache_policy.static.id
      response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    }
  }

  # The site's own certificate, by SNI, which every current browser supports.
  # TLSv1.2_2021 allows TLS 1.3 and 1.2. It keeps the ChaCha20 ciphers, which
  # are faster than AES on phones without AES hardware.
  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.name_prefix}-cdn"
  }
}

# The apex and www, each with an A record for IPv4 and an AAAA record for
# IPv6, as aliases to the distribution: apex-A, apex-AAAA, www-A, www-AAAA.
resource "aws_route53_record" "site" {
  for_each = {
    for pair in setproduct(keys(local.site_names), ["A", "AAAA"]) :
    "${pair[0]}-${pair[1]}" => { name = local.site_names[pair[0]], type = pair[1] }
  }

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name    = aws_cloudfront_distribution.this.domain_name
    zone_id = aws_cloudfront_distribution.this.hosted_zone_id
    # Route 53 rejects true for an alias to CloudFront, and only when it
    # creates the record, so a plan would not show the mistake.
    evaluate_target_health = false
  }
}
