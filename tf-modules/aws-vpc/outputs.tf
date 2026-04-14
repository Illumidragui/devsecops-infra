output "vpc_id" {
  description = "VPC ID"
  value       = var.create ? aws_vpc.main[0].id : null
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = var.create ? aws_subnet.public[0].id : null
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = var.create ? aws_subnet.private[0].id : null
}
