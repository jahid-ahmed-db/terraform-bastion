resource "aws_security_group" "bastion_security_group" {
  description = "Enable SSH access to the bastion host from external via SSH port"
  name        = "${var.name-prefix}-host"
  vpc_id      = var.vpc_id

  tags = merge(var.tags)
}

resource "aws_security_group_rule" "ingress_bastion" {
  description       = "Incoming traffic to bastion"
  type              = "ingress"
  from_port         = var.public_ssh_port
  to_port           = var.public_ssh_port
  protocol          = "TCP"
  cidr_blocks       = concat(data.aws_subnet.subnets.*.cidr_block, var.cidrs)
  security_group_id = aws_security_group.bastion_security_group.id
}

resource "aws_security_group_rule" "egress_bastion" {
  description = "Outgoing traffic from bastion to instances"
  type        = "egress"
  from_port   = "0"
  to_port     = "65535"
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_security_group.id
}

resource "aws_security_group" "instances_security_group" {
  description = "Allow SSH from the bastion to private instances"
  name        = "${var.name-prefix}-instances"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags)
}

resource "aws_security_group_rule" "ingress_instances" {
  description              = "Incoming traffic from bastion"
  type                     = "ingress"
  from_port                = var.public_ssh_port
  to_port                  = var.public_ssh_port
  protocol                 = "TCP"
  source_security_group_id = aws_security_group.bastion_security_group.id
  security_group_id        = aws_security_group.instances_security_group.id
}

resource "aws_route53_record" "bastion_record_name" {
  name    = var.bastion_record_name
  zone_id = var.hosted_zone_name
  type    = "A"
  count   = var.create_dns_record ? 1 : 0

  alias {
    evaluate_target_health = true
    name                   = aws_lb.bastion_lb.dns_name
    zone_id                = aws_lb.bastion_lb.zone_id
  }
}

resource "aws_lb" "bastion_lb" {
  internal           = var.is_lb_private
  name               = "${var.name-prefix}-lb"
  subnets            = var.elb_subnets
  load_balancer_type = "network"
  tags               = merge(var.tags)
}

resource "aws_lb_target_group" "bastion_lb_target_group" {
  name        = "${var.name-prefix}-lb-target"
  port        = var.public_ssh_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    port     = "traffic-port"
    protocol = "TCP"
  }
  tags = merge(var.tags)
}

resource "aws_lb_listener" "bastion_lb_listener_22" {
  default_action {
    target_group_arn = aws_lb_target_group.bastion_lb_target_group.arn
    type             = "forward"
  }

  load_balancer_arn = aws_lb.bastion_lb.arn
  port              = var.public_ssh_port
  protocol          = "TCP"
}

resource "aws_launch_configuration" "bastion_launch_configuration" {
  image_id                    = data.aws_ami.amazon-linux-2.id
  instance_type               = var.instance_type
  associate_public_ip_address = var.associate_public_ip_address
  enable_monitoring           = true
  key_name                    = var.bastion_host_key_pair

  security_groups = [
    aws_security_group.bastion_security_group.id,
  ]

  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion_auto_scaling_group" {
  name                 = "ASG-${var.bastion_launch_configuration_name}"
  launch_configuration = aws_launch_configuration.bastion_launch_configuration.name
  max_size             = var.bastion_instance_count
  min_size             = var.bastion_instance_count
  desired_capacity     = var.bastion_instance_count

  vpc_zone_identifier = var.auto_scaling_group_subnets

  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  target_group_arns = [
    aws_lb_target_group.bastion_lb_target_group.arn,
  ]

  termination_policies = [
    "OldestLaunchConfiguration",
  ]

  tags = [
    {
      key                 = "Name"
      value               = "ASG-${var.bastion_launch_configuration_name}"
      propagate_at_launch = true
    }
  ]


  lifecycle {
    create_before_destroy = true
  }
}

