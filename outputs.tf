output "instance_ip" {
  description = "Public IP of the k3s EC2 instance"
  value       = module.aws.instance_ip
}