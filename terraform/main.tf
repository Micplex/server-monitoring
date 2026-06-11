terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" { region = var.aws_region }

resource "aws_instance" "monitoring" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y && apt-get install -y git docker.io docker-compose
    git clone https://github.com/YOUR_REPO/linux-monitoring-suite /opt/monitoring
    cd /opt/monitoring && cp .env.example .env && bash cron/install-cron.sh
  EOF
  tags = { Name = "monitoring-server", Environment = var.environment }
}
output "ip" { value = aws_instance.monitoring.public_ip }
