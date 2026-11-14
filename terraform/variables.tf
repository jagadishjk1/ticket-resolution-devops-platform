variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for resource names and tags."
  type        = string
  default     = "ticket-swarm"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "manager_instance_type" {
  description = "Instance type for the Swarm manager (also runs Prometheus, Grafana, Loki)."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Swarm workers."
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of Swarm worker nodes (Auto Scaling Group size)."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count must be between 1 and 10."
  }
}

variable "manager_root_volume_gb" {
  description = "Root volume size for the manager (holds Prometheus/Loki/Grafana data)."
  type        = number
  default     = 30
}

variable "worker_root_volume_gb" {
  description = "Root volume size for workers."
  type        = number
  default     = 20
}

variable "ami_id" {
  description = "Optional AMI override. Empty = latest Ubuntu 24.04 LTS (Canonical)."
  type        = string
  default     = ""
}

variable "public_key_path" {
  description = "Path to the SSH public key to install on the nodes."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH (22), Grafana (3000), Prometheus (9090) and Alertmanager (9093). Use your own IP, e.g. [\"203.0.113.10/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must be non-empty and must not contain 0.0.0.0/0 (do not expose admin ports to the internet)."
  }
}

variable "app_ingress_cidrs" {
  description = "CIDRs allowed to reach the application on port 80."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
