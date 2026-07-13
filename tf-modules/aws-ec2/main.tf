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
  key_name   = "${local.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

#checkov:skip=CKV_AWS_382:All outbound is required for Tailscale, k3s, and OS package installs on this single-node lab instance.
#checkov:skip=CKV_AWS_260:Public website traffic must reach this instance directly; there is no NLB in front of it in this architecture.
resource "aws_security_group" "k3s" {
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

  # No AWS NLB in this architecture — the EIP on this instance is the direct
  # ingress path for the website; ingress-nginx handles routing/TLS once
  # traffic reaches the node.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP - direct ingress, routed by ingress-nginx"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS - direct ingress, routed by ingress-nginx"
  }

  # Tailscale WireGuard — required for direct peer connections (without this, falls back to slow DERP relay)
  ingress {
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Tailscale WireGuard"
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

# Minimal instance profile so the node isn't credential-less. SSM Session
# Manager also gives a Tailscale-independent break-glass access path — the
# AL2023 AMI ships with the SSM agent pre-installed and running.
resource "aws_iam_role" "k3s" {
  name = "${local.name_prefix}-k3s-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-k3s-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k3s" {
  name = "${local.name_prefix}-k3s-profile"
  role = aws_iam_role.k3s.name
}

#checkov:skip=CKV_AWS_88:No AWS NLB in this architecture; the EIP+public IP on this instance IS the ingress path for the website and Tailscale. Removing it would break public access.
#checkov:skip=CKV_AWS_126:Personal lab, FinOps zero-idle-cost goal — detailed monitoring costs ~$2.10/mo/instance with no operational benefit for a single-node dev cluster.
resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = aws_key_pair.main.key_name
  iam_instance_profile        = aws_iam_instance_profile.k3s.name
  associate_public_ip_address = true
  ebs_optimized               = true

  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Start Tailscale daemon and join the network
    systemctl enable --now tailscaled
    tailscale up --authkey=${var.tailscale_authkey} --hostname=${var.tailscale_hostname} --advertise-tags=tag:k3s

    # Wait for Tailscale to receive its IP (can take a few seconds after `tailscale up`)
    for i in $(seq 1 12); do
      TAILSCALE_IP=$(tailscale ip -4 2>/dev/null) && [ -n "$TAILSCALE_IP" ] && break
      [ $i -eq 12 ] && { echo "Timed out waiting for Tailscale IP"; exit 1; }
      sleep 5
    done

    # Install k3s with Tailscale IP as TLS SAN so kubectl works over the VPN
    curl -sfL https://get.k3s.io | sh -s - --tls-san "$TAILSCALE_IP" --disable traefik

    # Make kubeconfig readable so it can be copied out via SSH
    chmod 644 /etc/rancher/k3s/k3s.yaml
  EOF
  )

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${local.name_prefix}-k3s-node"
  }
}
