output "instance_id" {
  description = "EC2 instance ID"
  value       = var.create ? aws_instance.k3s[0].id : null
}

output "instance_ip" {
  description = "Private IP of the k3s EC2 instance (access via Tailscale)"
  value       = var.create ? aws_instance.k3s[0].private_ip : null
}

output "tailscale_hostname" {
  description = "Hostname of the k3s node in the Tailscale network"
  value       = var.tailscale_hostname
}
