output "monitoring_ip"  { value = aws_instance.monitoring.public_ip }
output "ssh_connect"    { value = "ssh ubuntu@${aws_instance.monitoring.public_ip}" }
