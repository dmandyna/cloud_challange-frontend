resource "aws_s3_bucket" "site" {
  bucket = "dmandyna.com"
  acl    = "public-read"

  website {
    index_document = "index.html"
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "null_resource" "upload_s3_content" {
  provisioner "local-exec" {
    command = "aws s3 sync ${path.module}/src s3://${aws_s3_bucket.site.id}"
  }
}

resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.site.cloudfront_access_identity_path
    }
  }

  aliases = ["www.dmandyna.co.uk", "*.dmandyna.co.uk"]

  price_class = "PriceClass_100"
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for Cloud Resume"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.personal.certificate_arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_cloudfront_origin_access_identity" "site" {
  comment = "Origin Access Identity for Cloud Resume"
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "dmandyna.co.uk"
  subject_alternative_names = ["www.dmandyna.co.uk", "dmandyna.co.uk", "*.dmandyna.co.uk"]
  validation_method = "DNS"

  tags = {
    Name = "Personal Project SSL Cert"
  }

  lifecycle {
    create_before_destroy = true
  }
  provider = aws.nv
}

resource "aws_route53_record" "personal" {
  for_each = {
    for entry in aws_acm_certificate.cert.domain_validation_options : entry.domain_name => {
      name   = entry.resource_record_name
      record = entry.resource_record_value
      type   = entry.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.personal_page.zone_id
}

resource "aws_acm_certificate_validation" "personal" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.personal : record.fqdn]
  provider                = aws.nv
}