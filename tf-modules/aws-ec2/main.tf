# Latest Amazon Linux 2 AMI (arm64 for cost efficiency, or x86_64 for t2.micro free tier)
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

resource "aws_key_pair" "main" {
  count      = var.create ? 1 : 0
  key_name   = "${local.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

resource "aws_security_group" "k3s" {
  count       = var.create ? 1 : 0
  name        = "${local.name_prefix}-k3s-sg"
  description = "Security group for the k3s node - inbound from VPC only, Tailscale handles external access"
  vpc_id      = var.vpc_id

  # Allow all traffic within the VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "All traffic from within the VPC"
  }

  # k3s API server — needed for kubectl via Tailscale
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "k3s API server"
  }

  # HTTP/HTTPS from NLB — NLB preserves source IP so SG must allow 0.0.0.0/0
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from NLB"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from NLB"
  }

  # Allow all outbound — needed for Tailscale, k3s, package downloads
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-k3s-sg"
  }
}

resource "aws_instance" "k3s" {
  count                       = var.create ? 1 : 0
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.k3s[0].id]
  key_name                    = aws_key_pair.main[0].key_name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Start Tailscale daemon and join the network
    systemctl enable --now tailscaled
    tailscale up --authkey=${var.tailscale_authkey} --hostname=${var.tailscale_hostname} --advertise-tags=tag:k3s

    # Install k3s with Tailscale IP as TLS SAN so kubectl works over the VPN
    TAILSCALE_IP=$(tailscale ip -4)
    curl -sfL https://get.k3s.io | sh -s - --tls-san "$TAILSCALE_IP" --disable traefik

    # Make kubeconfig readable so it can be copied out via SSH
    chmod 644 /etc/rancher/k3s/k3s.yaml
  EOF
  )

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${local.name_prefix}-k3s-node"
  }
}
