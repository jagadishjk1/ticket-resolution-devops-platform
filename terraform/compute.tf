data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
}

resource "aws_key_pair" "admin" {
  key_name_prefix = "${local.name}-"
  public_key      = file(pathexpand(var.public_key_path))
}

# ---------------------------------------------------------------- manager
resource "aws_instance" "manager" {
  ami                    = local.ami_id
  instance_type          = var.manager_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.swarm.id]
  key_name               = aws_key_pair.admin.key_name
  iam_instance_profile   = aws_iam_instance_profile.manager.name

  user_data = templatefile("${path.module}/templates/manager.sh.tftpl", {
    region     = var.region
    ssm_prefix = local.ssm_prefix
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.manager_root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.name}-manager"
    Role = "swarm-manager"
  }

  # Replacing the manager destroys the Swarm state (Raft) and all monitoring data,
  # so neither a newer AMI nor edited bootstrap script may recreate it implicitly.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [
    aws_ssm_parameter.worker_token,
    aws_ssm_parameter.manager_addr,
    aws_iam_role_policy.manager,
  ]
}

resource "aws_eip" "manager" {
  domain   = "vpc"
  instance = aws_instance.manager.id

  tags = { Name = "${local.name}-manager" }

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------- workers (self-healing ASG)
resource "aws_launch_template" "worker" {
  name_prefix   = "${local.name}-worker-"
  image_id      = local.ami_id
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.admin.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  user_data = base64encode(templatefile("${path.module}/templates/worker.sh.tftpl", {
    region     = var.region
    ssm_prefix = local.ssm_prefix
  }))

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.swarm.id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.worker_root_volume_gb
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${local.name}-worker"
      Role = "swarm-worker"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "${local.name}-worker"
    }
  }

  update_default_version = true
}

resource "aws_autoscaling_group" "worker" {
  name_prefix         = "${local.name}-worker-"
  min_size            = var.worker_count
  max_size            = var.worker_count
  desired_capacity    = var.worker_count
  vpc_zone_identifier = aws_subnet.public[*].id

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-worker"
    propagate_at_launch = true
  }

  depends_on = [aws_instance.manager]

  lifecycle {
    create_before_destroy = true
  }
}
