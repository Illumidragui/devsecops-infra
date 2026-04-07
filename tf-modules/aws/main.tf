#VPC y red
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# VPC — red privada aislada para nuestros recursos
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${local.name_prefix}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Subnet pública — donde vivirá la EC2
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${local.name_prefix}-public-subnet"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Internet Gateway — permite tráfico hacia/desde internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-igw"
    ManagedBy = "terraform"
  }
}

# Route table — dirige el tráfico de la subnet al internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name      = "${local.name_prefix}-rt"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group — el firewall de la instancia
resource "aws_security_group" "k3s" {
  name        = "${local.name_prefix}-k3s-sg"
  description = "Security group for k3s node"
  vpc_id      = aws_vpc.main.id

  # SSH — solo desde tu IP
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Kubernetes API — solo desde tu IP
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Todo el tráfico saliente permitido
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

# Key pair — registra tu clave pública en AWS
resource "aws_key_pair" "main" {
  key_name   = "${local.name_prefix}-key"
  public_key = var.ssh_public_key

  tags = {
    ManagedBy = "terraform"
  }
}

# AMI más reciente de Amazon Linux 2023
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

# EC2 con k3s instalado automáticamente via user_data
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = aws_key_pair.main.key_name

  user_data = <<-EOF
    #!/bin/bash
    curl -sfL https://get.k3s.io | sh -
    chmod 644 /etc/rancher/k3s/k3s.yaml
  EOF

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name        = "${local.name_prefix}-k3s-node"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}