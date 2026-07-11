output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "instance_ip" {
  description = "Private IP of the k3s EC2 instance (access via Tailscale)"
  value       = aws_instance.k3s.private_ip
}

output "tailscale_hostname" {
  description = "Hostname of the k3s node in the Tailscale network"
  value       = var.tailscale_hostname
}

