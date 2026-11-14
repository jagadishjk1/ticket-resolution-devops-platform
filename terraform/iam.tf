data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  ssm_prefix = "/${var.project_name}/${var.environment}/swarm"
  ssm_arn    = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------- manager
resource "aws_iam_role" "manager" {
  name_prefix        = "${local.name}-manager-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "manager" {
  statement {
    sid       = "PublishSwarmJoinInfo"
    actions   = ["ssm:PutParameter", "ssm:GetParameter"]
    resources = [local.ssm_arn]
  }
}

resource "aws_iam_role_policy" "manager" {
  name   = "swarm-join-info"
  role   = aws_iam_role.manager.id
  policy = data.aws_iam_policy_document.manager.json
}

resource "aws_iam_role_policy_attachment" "manager_ssm" {
  role       = aws_iam_role.manager.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "manager" {
  name_prefix = "${local.name}-manager-"
  role        = aws_iam_role.manager.name
}

# ---------------------------------------------------------------- workers (read-only)
resource "aws_iam_role" "worker" {
  name_prefix        = "${local.name}-worker-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid       = "ReadSwarmJoinInfo"
    actions   = ["ssm:GetParameter"]
    resources = [local.ssm_arn]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "swarm-join-info-read"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker" {
  name_prefix = "${local.name}-worker-"
  role        = aws_iam_role.worker.name
}

# ---------------------------------------------------------------- join info in SSM Parameter Store
# Created here (with a placeholder) so `terraform destroy` removes them. The manager
# overwrites the values at boot; Terraform ignores the value afterwards.
resource "aws_ssm_parameter" "worker_token" {
  name  = "${local.ssm_prefix}/worker-token"
  type  = "SecureString"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "manager_addr" {
  name  = "${local.ssm_prefix}/manager-addr"
  type  = "String"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}
