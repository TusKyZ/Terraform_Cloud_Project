# The internet-facing Application Load Balancer, in the public subnets. Its
# security group lets in HTTPS only from CloudFront.
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]

  # Headers whose names are not valid HTTP are dropped, not passed on to
  # WordPress.
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# The WordPress instances, on HTTP port 80 inside the VPC: HTTPS ends at the
# ALB.
resource "aws_lb_target_group" "app" {
  # checkov:skip=CKV_AWS_378:False positive. The HTTPS listener reaches this target group through its rule, and this graph check only looks for a listener that forwards to it directly. TLS ends at the ALB, so ALB to EC2 is plain HTTP inside the VPC; end-to-end TLS is a next step.
  name_prefix = "app-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  # WordPress pages finish in seconds, so a leaving instance needs little time
  # to finish its requests. The default, 300 seconds, would hold every
  # scale-in and instance refresh for 5 minutes per instance.
  deregistration_delay = 30

  health_check {
    path = "/"
    # WordPress answers the home page with 200 once installed, and with a
    # redirect before that or when the request's host name is not the site's.
    matcher = "200-399"
  }

  tags = {
    Name = "${var.name_prefix}-app-tg"
  }

  # AWS cannot delete a target group that a listener rule still uses, so a
  # replacement is created first; name_prefix keeps the two names apart.
  lifecycle {
    create_before_destroy = true
  }
}

# The only listener: HTTPS on port 443. There is no port 80 listener, because
# only CloudFront connects, and always over HTTPS.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  # AWS's recommended policy: TLS 1.3 and 1.2 only, with only AES-GCM ciphers
  # for TLS 1.2. Its post-quantum key exchange goes unused here: CloudFront,
  # the only client, connects to origins with classical key exchange. Without
  # a policy, the API default is ELBSecurityPolicy-2016-08, which still
  # allows TLS 1.0.
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn = var.alb_certificate_arn

  # Requests that no rule forwards get a 403 from the ALB itself.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# CloudFront adds the X-Origin-Verify header, carrying the secret, to every
# request it sends here. The security group already limits the ALB to
# CloudFront's addresses, but every CloudFront distribution shares those, so
# only requests with our secret reach WordPress; the rest get the default 403.
resource "aws_lb_listener_rule" "origin_verify" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

# CloudFront connects to the ALB by this name, which the ALB's certificate
# covers. With the ALB's own DNS name, CloudFront's certificate check would
# fail and viewers would get a 502.
resource "aws_route53_record" "origin" {
  zone_id = var.zone_id
  name    = "origin.${var.domain_name}"
  type    = "A"

  alias {
    name    = aws_lb.this.dns_name
    zone_id = aws_lb.this.zone_id
    # With one simple record, Route 53 answers with it whatever the ALB's
    # health, so evaluating target health would change nothing.
    evaluate_target_health = false
  }
}
