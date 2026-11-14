locals {
  admin_ports = [22, 3000, 9090, 9093]

  # One rule per (port, cidr) pair
  admin_rules = {
    for pair in setproduct(local.admin_ports, var.admin_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
  }

  app_rules = { for cidr in var.app_ingress_cidrs : cidr => cidr }

  # Ports Docker Swarm needs between nodes
  swarm_internal = {
    "cluster-mgmt-2377-tcp" = { port = 2377, proto = "tcp" }
    "gossip-7946-tcp"       = { port = 7946, proto = "tcp" }
    "gossip-7946-udp"       = { port = 7946, proto = "udp" }
    "overlay-vxlan-4789"    = { port = 4789, proto = "udp" }
  }
}

resource "aws_security_group" "swarm" {
  name_prefix = "${local.name}-swarm-"
  description = "Docker Swarm nodes"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-swarm" }

  lifecycle {
    create_before_destroy = true
  }
}

# Node-to-node traffic (only members of this security group)
resource "aws_vpc_security_group_ingress_rule" "swarm_internal" {
  for_each = local.swarm_internal

  security_group_id            = aws_security_group.swarm.id
  referenced_security_group_id = aws_security_group.swarm.id
  ip_protocol                  = each.value.proto
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = "Swarm ${each.key}"
}

# Public application traffic (served through the Swarm routing mesh on every node)
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each = local.app_rules

  security_group_id = aws_security_group.swarm.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "Application HTTP"
}

# Administration: SSH + observability UIs, restricted to the operator's CIDRs
resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each = local.admin_rules

  security_group_id = aws_security_group.swarm.id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "Admin port ${each.value.port}"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.swarm.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound (package installs, image pulls, SSM)"
}
