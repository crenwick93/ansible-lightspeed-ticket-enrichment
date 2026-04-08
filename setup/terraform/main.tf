terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── SSH key pair (generated, never leaves the machine) ─────────

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "demo" {
  key_name_prefix = "prom-alertmgr-demo-"
  public_key      = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/demo-key.pem"
  file_permission = "0600"
}

# ── Security group ─────────────────────────────────────────────

resource "aws_security_group" "monitoring" {
  name_prefix = "prom-alertmgr-demo-"
  description = "Prometheus + AlertManager + httpd demo"

  dynamic "ingress" {
    for_each = {
      ssh        = { port = 22, desc = "SSH" }
      http       = { port = 80, desc = "httpd hello-world" }
      prometheus = { port = 9090, desc = "Prometheus UI" }
      alertmgr   = { port = 9093, desc = "AlertManager UI" }
      node_exp   = { port = 9100, desc = "Node Exporter metrics" }
    }
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = [var.allowed_cidr]
      description = ingress.value.desc
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "prom-alertmgr-demo" }
}

# ── EC2 instance ───────────────────────────────────────────────

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "prom-alertmgr-demo" }
}

# ── Generated Ansible inventory ───────────────────────────────

resource "local_file" "ansible_inventory" {
  content = <<-YAML
    all:
      hosts:
        monitoring:
          ansible_host: ${aws_instance.monitoring.public_ip}
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ${local_sensitive_file.ssh_private_key.filename}
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  YAML

  filename        = "${path.module}/../playbooks/inventory/hosts.yml"
  file_permission = "0644"
}
