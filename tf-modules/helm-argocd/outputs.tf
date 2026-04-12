# tf-modules/aws/outputs.tf
output "instance_ip" {
  description = "Public IP of the k3s EC2 instance"
  value       = aws_instance.k3s.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.k3s.id
}