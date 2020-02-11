output "elb_ip" {
  value = aws_lb.bastion_lb.dns_name
}

output "bastion_security_group" {
  value = aws_security_group.bastion_security_group.id
}

output "instances_security_group" {
  value = aws_security_group.instances_security_group.id
}

