output "tailscale_hostname" {
  description = "Hostname of the k3s node in the Tailscale network"
  value       = module.ec2.tailscale_hostname
}

output "public_ip" {
  description = "Elastic IP — use this as A record for shengjunye.me"
  value       = aws_eip.k3s.public_ip
}
