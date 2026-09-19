terraform {
  required_version = ">= 1.5"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Découverte automatique du VPC, du subnet et de l'AMI Ubuntu si non fournis
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "public" {
  count = var.subnet_id == "" ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [coalesce(var.vpc_id, data.aws_vpc.default[0].id)]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  count = var.subnet_id == "" ? 1 : 0
  id    = data.aws_subnets.public[0].ids[0]
}

data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  env_suffix = var.environment
  vpc_id     = coalesce(var.vpc_id, data.aws_vpc.default[0].id)
  subnet_id  = coalesce(var.subnet_id, data.aws_subnet.selected[0].id)
  ami_id     = coalesce(var.ami_id, data.aws_ami.ubuntu[0].id)
}

# Groupe de sécurité public (HTTP / HTTPS / SSH / monitoring)
resource "aws_security_group" "public_sg" {
  name        = "${var.project_name}-${local.env_suffix}-sg"
  description = "Public HTTP/HTTPS/SSH/monitoring for ${local.env_suffix}"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Monitoring (Traefik dashboard, Prometheus, Grafana)"
    from_port   = 8080
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instance EC2 avec une adresse IP publique dynamique (et EIP optionnel dans outputs)
resource "aws_instance" "web" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  subnet_id              = local.subnet_id
  key_name               = var.key_name

  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    # Mise à jour et installation de base
    apt-get update -y
    apt-get install -y python3 python3-apt gnupg ca-certificates curl git
  EOF

  tags = {
    Name = "${var.project_name}-${local.env_suffix}"
    Env  = local.env_suffix
    Role = "web"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }
}

# Adresse IP élastique stable (utile pour le DNS / Ansible inventory)
resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${local.env_suffix}-eip"
  }
}

# Enregistrement DNS (si un domaine est configuré)
resource "aws_route53_record" "app" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "300"
  records = [aws_eip.web.public_ip]
}