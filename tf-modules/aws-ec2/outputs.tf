output "instance_ip" {
  description = "Elastic IP of the k3s EC2 instance"
  value       = aws_eip.k3s.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k3s.id
}