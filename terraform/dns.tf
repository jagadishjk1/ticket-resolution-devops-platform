# Optional DNS: friendly names for the manager's Elastic IP in an EXISTING public
# Route53 hosted zone. Leave hosted_zone_name empty to skip all of this.
# Records are created by Terraform and removed by `terraform destroy`; the zone
# itself is only looked up, never created, modified or deleted.
locals {
  dns_enabled = var.hosted_zone_name != ""

  dns_records = local.dns_enabled ? {
    app        = "${var.app_subdomain}.${var.hosted_zone_name}"
    grafana    = "grafana.${var.app_subdomain}.${var.hosted_zone_name}"
    prometheus = "prometheus.${var.app_subdomain}.${var.hosted_zone_name}"
    alerts     = "alerts.${var.app_subdomain}.${var.hosted_zone_name}"
  } : {}
}

data "aws_route53_zone" "selected" {
  count = local.dns_enabled ? 1 : 0

  name         = var.hosted_zone_name
  private_zone = false
}

# allow_overwrite is left at its default (false): if a record with the same name
# already exists, apply fails instead of silently replacing it.
resource "aws_route53_record" "this" {
  for_each = local.dns_records

  zone_id = data.aws_route53_zone.selected[0].zone_id
  name    = each.value
  type    = "A"
  ttl     = 300
  records = [aws_eip.manager.public_ip]
}
