# -----------------------------------------------------------------------------
# WireGuard on ECS (EC2 launch type) — reach MSK in the streaming VPC from laptop
# Requires enable_msk = true (same VPC). Inbound UDP only from vpn_admin_cidr.
# -----------------------------------------------------------------------------

check "vpn_requires_msk_vpc" {
  assert {
    condition     = !var.enable_vpn || var.enable_msk
    error_message = "enable_vpn requires enable_msk (uses aws_vpc.streaming)."
  }
}

# --- Internet access for VPN ECS and/or SSH bastion (MSK subnets stay on main / private RT)
resource "aws_internet_gateway" "streaming" {
  count  = local.streaming_public_network ? 1 : 0
  vpc_id = aws_vpc.streaming[0].id

  tags = { Name = "medcore-streaming-igw" }
}

resource "aws_subnet" "streaming_public" {
  count                   = local.streaming_public_network ? 1 : 0
  vpc_id                  = aws_vpc.streaming[0].id
  cidr_block              = cidrsubnet(aws_vpc.streaming[0].cidr_block, 8, 10)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "medcore-streaming-public" }
}

resource "aws_route_table" "streaming_public" {
  count  = local.streaming_public_network ? 1 : 0
  vpc_id = aws_vpc.streaming[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.streaming[0].id
  }

  tags = { Name = "medcore-streaming-public-rt" }
}

resource "aws_route_table_association" "streaming_public" {
  count          = local.streaming_public_network ? 1 : 0
  subnet_id      = aws_subnet.streaming_public[0].id
  route_table_id = aws_route_table.streaming_public[0].id
}

# --- Security: WireGuard UDP only from your IP; EFS NFS from ECS instances only
resource "aws_security_group" "vpn_ecs_instances" {
  count       = var.enable_msk && var.enable_vpn ? 1 : 0
  name_prefix = "medcore-vpn-ecs-"
  description = "ECS WireGuard host - WG from admin CIDR only"
  vpc_id      = aws_vpc.streaming[0].id

  ingress {
    description = "WireGuard"
    from_port   = var.vpn_wireguard_port
    to_port     = var.vpn_wireguard_port
    protocol    = "udp"
    cidr_blocks = [var.vpn_admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "medcore-vpn-ecs-sg" }
}

resource "aws_security_group" "vpn_efs" {
  count       = var.enable_msk && var.enable_vpn ? 1 : 0
  name_prefix = "medcore-vpn-efs-"
  description = "EFS for WireGuard configs"
  vpc_id      = aws_vpc.streaming[0].id

  ingress {
    description     = "NFS from ECS instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_ecs_instances[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "medcore-vpn-efs-sg" }
}

resource "aws_efs_file_system" "wireguard" {
  count          = var.enable_msk && var.enable_vpn ? 1 : 0
  creation_token = "medcore-wireguard-config"
  encrypted      = true

  tags = { Name = "medcore-wireguard-config" }
}

resource "aws_efs_mount_target" "wireguard" {
  count           = var.enable_msk && var.enable_vpn ? 2 : 0
  file_system_id  = aws_efs_file_system.wireguard[0].id
  subnet_id       = aws_subnet.streaming[count.index].id
  security_groups = [aws_security_group.vpn_efs[0].id]
}

# --- ECS cluster + EC2 capacity (Fargate cannot run WireGuard with tun/NAT)
data "aws_ssm_parameter" "ecs_ami_al2" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

resource "aws_iam_role" "vpn_ecs_instance" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "medcore-vpn-ecs-instance" }
}

resource "aws_iam_role_policy_attachment" "vpn_ecs_instance" {
  count      = var.enable_msk && var.enable_vpn ? 1 : 0
  role       = aws_iam_role.vpn_ecs_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "vpn_ecs_instance_ssm" {
  count      = var.enable_msk && var.enable_vpn ? 1 : 0
  role       = aws_iam_role.vpn_ecs_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vpn_ecs_instance" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn-ecs-instance"
  role  = aws_iam_role.vpn_ecs_instance[0].name
}

resource "aws_iam_role" "vpn_ecs_execution" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpn_ecs_execution" {
  count      = var.enable_msk && var.enable_vpn ? 1 : 0
  role       = aws_iam_role.vpn_ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "vpn_ecs_execution_efs" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "efs-mount"
  role  = aws_iam_role.vpn_ecs_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.wireguard[0].arn
      }
    ]
  })
}

resource "aws_iam_role" "vpn_ecs_task" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_ecs_cluster" "vpn" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = { Name = "medcore-vpn" }
}

locals {
  vpn_cluster_name = length(aws_ecs_cluster.vpn) > 0 ? aws_ecs_cluster.vpn[0].name : ""
}

resource "aws_cloudwatch_log_group" "wireguard" {
  count             = var.enable_msk && var.enable_vpn ? 1 : 0
  name              = "/ecs/medcore-wireguard"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "vpn_ecs_execution_logs" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "cloudwatch-logs"
  role  = aws_iam_role.vpn_ecs_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.wireguard[0].arn}:*"
    }]
  })
}

resource "aws_launch_template" "vpn_ecs" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  name_prefix   = "medcore-vpn-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami_al2[0].value
  instance_type = var.vpn_ecs_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.vpn_ecs_instance[0].name
  }

  vpc_security_group_ids = [aws_security_group.vpn_ecs_instances[0].id]

  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo ECS_CLUSTER=${local.vpn_cluster_name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_ENI=true >> /etc/ecs/ecs.config
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "medcore-vpn-ecs" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "medcore-vpn-ecs" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "vpn_ecs" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  name                      = "medcore-vpn-ecs-asg"
  vpc_zone_identifier       = [aws_subnet.streaming_public[0].id]
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.vpn_ecs[0].id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "medcore-vpn-ecs"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "vpn_ec2" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0
  name  = "medcore-vpn-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.vpn_ecs[0].arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "vpn" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  cluster_name = aws_ecs_cluster.vpn[0].name

  capacity_providers = [aws_ecs_capacity_provider.vpn_ec2[0].name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.vpn_ec2[0].name
  }
}

resource "aws_ecs_task_definition" "wireguard" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  family                   = "medcore-wireguard"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  execution_role_arn       = aws_iam_role.vpn_ecs_execution[0].arn
  task_role_arn            = aws_iam_role.vpn_ecs_task[0].arn

  volume {
    name = "wg-config"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.wireguard[0].id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config {
        iam = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name       = "wireguard"
    image      = "linuxserver/wireguard:latest"
    essential  = true
    privileged = true
    # EC2 launch type: required by RegisterTaskDefinition (not needed on Fargate the same way)
    memory = 256

    linuxParameters = {
      capabilities = {
        add = ["NET_ADMIN", "SYS_MODULE"]
      }
    }

    environment = [
      { name = "PUID", value = "1000" },
      { name = "PGID", value = "1000" },
      { name = "TZ", value = "UTC" },
      { name = "SERVERURL", value = "auto" },
      { name = "SERVERPORT", value = tostring(var.vpn_wireguard_port) },
      { name = "PEERS", value = tostring(var.vpn_peer_count) },
      { name = "LOG_CONFS", value = "true" }
    ]

    mountPoints = [{
      sourceVolume  = "wg-config"
      containerPath = "/config"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.wireguard[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "wg"
      }
    }
  }])

  depends_on = [aws_efs_mount_target.wireguard]
}

resource "aws_ecs_service" "wireguard" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  name            = "wireguard"
  cluster         = aws_ecs_cluster.vpn[0].id
  task_definition = aws_ecs_task_definition.wireguard[0].arn
  desired_count   = 1

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.vpn_ec2[0].name
    weight            = 100
  }

  timeouts {
    create = "20m"
    update = "20m"
  }

  depends_on = [
    aws_ecs_cluster_capacity_providers.vpn,
    aws_cloudwatch_log_group.wireguard
  ]
}

data "aws_instances" "vpn_ecs" {
  count = var.enable_msk && var.enable_vpn ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["medcore-vpn-ecs"]
  }

  filter {
    name   = "instance-state-name"
    values = ["pending", "running"]
  }

  depends_on = [
    aws_autoscaling_group.vpn_ecs,
    aws_ecs_service.wireguard
  ]
}
