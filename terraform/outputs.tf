output "manager_public_ip" {
  description = "Elastic IP of the Swarm manager."
  value       = aws_eip.manager.public_ip
}

output "app_url" {
  description = "Application URL (served on every node via the routing mesh)."
  value       = "http://${aws_eip.manager.public_ip}"
}

output "grafana_url" {
  description = "Grafana (admin_cidrs only)."
  value       = "http://${aws_eip.manager.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus (admin_cidrs only)."
  value       = "http://${aws_eip.manager.public_ip}:9090"
}

output "alertmanager_url" {
  description = "Alertmanager (admin_cidrs only)."
  value       = "http://${aws_eip.manager.public_ip}:9093"
}

output "ssh_command" {
  description = "SSH into the manager."
  value       = "ssh ubuntu@${aws_eip.manager.public_ip}"
}

output "docker_host" {
  description = "Use as DOCKER_HOST to run docker/stack commands against the cluster from your workstation or CI."
  value       = "ssh://ubuntu@${aws_eip.manager.public_ip}"
}

output "ssm_session_command" {
  description = "SSH-less shell on the manager through AWS Systems Manager."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.manager.id}"
}

output "worker_autoscaling_group" {
  description = "Name of the worker Auto Scaling Group."
  value       = aws_autoscaling_group.worker.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}
