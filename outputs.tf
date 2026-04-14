output "instance_ip" {
  description = "Private IP of the k3s EC2 instance (access via Tailscale)"
  value       = module.ec2.instance_ip
}

output "tailscale_hostname" {
  description = "Hostname of the k3s node in the Tailscale network"
  value       = module.ec2.tailscale_hostname
}
