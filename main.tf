data "aws_caller_identity" "this" {}
data "aws_region" "current" {}

data "aws_route53_zone" "root" {
  name = "${var.root_domain_name}."
}

//resource "aws_route53_zone" "subdomain" {
//  name = "${var.subdomain}.${var.root_domain_name}."
//}

//resource "aws_route53_record" "subdomain_root_records" {
//  zone_id = data.aws_route53_zone.root.zone_id
//  name = "${var.subdomain}.${var.root_domain_name}"
//  type = "NS"
//  ttl = "30"
//
//  records = [
//    aws_route53_zone.subdomain.name_servers[0],
//    aws_route53_zone.subdomain.name_servers[1],
//    aws_route53_zone.subdomain.name_servers[2],
//    aws_route53_zone.subdomain.name_servers[3],
//  ]
//}

//                                            www Bucket

resource "aws_s3_bucket" "www" {
  bucket = "www.${var.root_domain_name}"

  acl = "public-read"

  force_destroy = true
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::www.${var.root_domain_name}/*"]
    }
  ]
}
POLICY

  website {
    redirect_all_requests_to = "https://${var.root_domain_name}"
  }
}

//                                                    Cert

resource "aws_acm_certificate" "certificate" {
  //  domain_name = ".${var.root_domain_name}"
  domain_name = "${var.root_domain_name}"
  validation_method = "DNS"
//  TODO: Logic to include wildcard
//  subject_alternative_names = [
//    "*.${var.root_domain_name}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "default" {
  certificate_arn = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [
    aws_route53_record.cert_validation.fqdn,
  ]
}

resource "aws_route53_record" "cert_validation" {
  name = aws_acm_certificate.certificate.domain_validation_options[0].resource_record_name
  type = aws_acm_certificate.certificate.domain_validation_options[0].resource_record_type
//  zone_id = aws_route53_zone.subdomain.zone_id

  zone_id = data.aws_route53_zone.root.zone_id
  records = [
    aws_acm_certificate.certificate.domain_validation_options[0].resource_record_value,
  ]
  ttl = 60
}

//                                                          CloudFront

resource "aws_cloudfront_distribution" "www_distribution" {
  origin {
    custom_origin_config {
      http_port = "80"
      https_port = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }

    domain_name = aws_s3_bucket.www.website_endpoint
    origin_id = "www.${var.root_domain_name}"
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress = true
    allowed_methods = [
      "GET",
      "HEAD",
    ]
    cached_methods = [
      "GET",
      "HEAD",
    ]

    // This needs to match the `origin_id` above.
    target_origin_id = "www.${var.root_domain_name}"
    min_ttl = 0
    default_ttl = 86400
    max_ttl = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  aliases = [
    "www.${var.root_domain_name}",
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.default.certificate_arn
    ssl_support_method = "sni-only"
  }
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.root.zone_id
  name = "www.${var.root_domain_name}"
  type = "A"

  alias {
    name = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

//                                                  Root Redirect

resource "aws_s3_bucket" "root" {
  bucket = var.root_domain_name
  acl = "public-read"
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.root_domain_name}/*"]
    }
  ]
}
POLICY

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

}

resource "aws_cloudfront_distribution" "root_distribution" {
  origin {
    custom_origin_config {
      http_port = "80"
      https_port = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
    domain_name = aws_s3_bucket.root.website_endpoint
    origin_id = var.root_domain_name
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress = true
    allowed_methods = [
      "GET",
      "HEAD",
    ]
    cached_methods = [
      "GET",
      "HEAD",
    ]
    target_origin_id = var.root_domain_name
    min_ttl = 0
    default_ttl = 86400
    max_ttl = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  aliases = [
    var.root_domain_name
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.default.certificate_arn
    ssl_support_method = "sni-only"
  }
}

resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.root.zone_id

  // NOTE: name is blank here.
  name = ""
  type = "A"

  alias {
    name = aws_cloudfront_distribution.root_distribution.domain_name
    zone_id = aws_cloudfront_distribution.root_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

