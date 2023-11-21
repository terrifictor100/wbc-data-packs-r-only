
resource "aws_cloudfront_cache_policy" "cloudfront_cache_policy_for_s3_bucket" {
  name = "${var.service_name_hyphens}--${var.environment_hyphens}-Cache-Policy"
  min_ttl = 0
  default_ttl = 60
  max_ttl = 600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "distribution_for_s3_bucket" {
  comment = "${var.service_name_hyphens}--${var.environment_hyphens}"

  origin {
    domain_name = aws_s3_bucket.static_website_s3_bucket.bucket_regional_domain_name
    origin_id = "${var.service_name_hyphens}--${var.environment_hyphens}--S3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac_for_s3_bucket.id
  }

  price_class = "PriceClass_100"

  aliases = ["${var.dns_record_subdomain_including_dot}${data.aws_route53_zone.route_53_zone_for_our_domain.name}"]

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.certificate_validation_waiter.certificate_arn
    cloudfront_default_certificate = false
    minimum_protocol_version = "TLSv1"
    ssl_support_method = "sni-only"
  }

  default_root_object = "index.html"

  enabled = true
  is_ipv6_enabled = true

  default_cache_behavior {
    cache_policy_id = aws_cloudfront_cache_policy.cloudfront_cache_policy_for_s3_bucket.id
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "${var.service_name_hyphens}--${var.environment_hyphens}--S3-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress = true

    function_association {
      event_type = "viewer-request"
      function_arn = aws_cloudfront_function.http_basic_auth_function.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations = []
    }
  }
}

resource "aws_cloudfront_origin_access_control" "oac_for_s3_bucket" {
  name                              = "${var.service_name_hyphens}--${var.environment_hyphens}--oac_for_s3_bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "http_basic_auth_function" {
  name    = "${var.service_name_hyphens}--${var.environment_hyphens}--http-basic-auth-function"
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = <<EOT
function handler(event) {
  var authHeaders = event.request.headers.authorization;

  // Configure authentication
  var authUser = '${var.BASIC_AUTH_USERNAME}';
  var authPass = '${var.BASIC_AUTH_PASSWORD}';

  function b2a(a) {
    var c, d, e, f, g, h, i, j, o, b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=", k = 0, l = 0, m = "", n = [];
    if (!a) return a;
    do c = a.charCodeAt(k++), d = a.charCodeAt(k++), e = a.charCodeAt(k++), j = c << 16 | d << 8 | e,
    f = 63 & j >> 18, g = 63 & j >> 12, h = 63 & j >> 6, i = 63 & j, n[l++] = b.charAt(f) + b.charAt(g) + b.charAt(h) + b.charAt(i); while (k < a.length);
    return m = n.join(""), o = a.length % 3, (o ? m.slice(0, o - 3) :m) + "===".slice(o || 3);
  }

  // Construct the Basic Auth string
  var expected = 'Basic ' + b2a(authUser + ':' + authPass);

  // If an Authorization header is supplied and it's an exact match, pass the
  // request on through to CF/the origin without any modification.
  if (authHeaders && authHeaders.value === expected) {
    // Check if the URL is in folder format (i.e. doesn't have a filename at the end)
    if (event.request.uri.endsWith('/')) {
        event.request.uri += 'index.html';
    }
    return event.request;
  }

  // But if we get here, we must either be missing the auth header or the
  // credentials failed to match what we expected.
  // Request the browser present the Basic Auth dialog.
  var response = {
    statusCode: 401,
    statusDescription: "Unauthorized",
    headers: {
      "www-authenticate": {
        value: 'Basic realm="Inclusion Confident Scheme design history"',
      },
    },
  };

  return response;
}
EOT
}
