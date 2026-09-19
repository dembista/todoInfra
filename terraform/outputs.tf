output "instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Adresse IP publique de l'instance"
  value       = aws_eip.web.public_ip
}

output "public_dns" {
  description = "Nom DNS public de l'instance"
  value       = aws_instance.web.public_dns
}

output "ssh_command" {
  description = "Commande SSH pour accéder à l'instance"
  value       = "ssh -i ../todo-app/todo-app.pem ubuntu@${aws_eip.web.public_ip}"
}