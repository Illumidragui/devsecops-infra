locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "k3s" {
  name        = "${local.name_prefix}-k3s-sg"
  description = "Security group for k3s node"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name_prefix}-k3s-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_key_pair" "main" {
  key_name   = "${local.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = {
    ManagedBy = "terraform"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = aws_key_pair.main.key_name

  user_data = <<-EOF
    #!/bin/bash
    PUBLIC_IP=$(curl -s ifconfig.me)
    curl -sfL https://get.k3s.io | sh -s - --tls-san $PUBLIC_IP
    chmod 644 /etc/rancher/k3s/k3s.yaml
  EOF

  root_block_device {
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name        = "${local.name_prefix}-k3s-node"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = {
    Name        = "${local.name_prefix}-eip"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}