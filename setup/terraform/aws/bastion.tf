# -----------------------------------------------------------------------------
# One EC2 in the streaming VPC public subnet: SSH from your home IP only.
# MSK bootstrap DNS resolves on the instance; no WireGuard or VPC DNS on Mac.
# -----------------------------------------------------------------------------

check "bastion_requires_msk" {
  assert {
    condition     = !var.enable_bastion || var.enable_msk
    error_message = "enable_bastion requires enable_msk (same VPC as MSK)."
  }
}

check "bastion_requires_ssh_key" {
  assert {
    condition     = !var.enable_bastion || length(trimspace(var.bastion_ssh_public_key)) > 0
    error_message = "Set bastion_ssh_public_key in terraform.tfvars to one line from: cat ~/.ssh/id_ed25519.pub"
  }
}

data "aws_ssm_parameter" "bastion_al2023_ami" {
  count = var.enable_msk && var.enable_bastion ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "bastion" {
  count      = var.enable_msk && var.enable_bastion ? 1 : 0
  key_name   = "medcore-bastion-book"
  public_key = trimspace(var.bastion_ssh_public_key)
}

resource "aws_security_group" "bastion" {
  count       = var.enable_msk && var.enable_bastion ? 1 : 0
  name_prefix = "medcore-bastion-"
  description = "SSH from bastion_ssh_cidr only"
  vpc_id      = aws_vpc.streaming[0].id

  ingress {
    description = "SSH from admin home IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "medcore-bastion-sg" }
}

resource "aws_iam_role" "bastion" {
  count = var.enable_msk && var.enable_bastion ? 1 : 0
  name  = "medcore-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "medcore-bastion" }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count      = var.enable_msk && var.enable_bastion ? 1 : 0
  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# MSK Serverless data-plane IAM: explicit ARNs (AmazonMSKFullAccess alone is often not enough / wrong resource shape).
resource "aws_iam_role_policy" "bastion_msk_serverless" {
  count = var.enable_msk && var.enable_bastion ? 1 : 0
  name  = "msk-serverless-producer"
  role  = aws_iam_role.bastion[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KafkaControlPlane"
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:DescribeClusterV2",
          "kafka:GetBootstrapBrokers"
        ]
        Resource = aws_msk_serverless_cluster.fraud_events[0].arn
      },
      {
        Sid    = "KafkaClusterConnect"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = aws_msk_serverless_cluster.fraud_events[0].arn
      },
      {
        Sid    = "KafkaTopics"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DeleteTopic"
        ]
        Resource = [
          # MSK Serverless topic ARNs use cluster name + UUID in the path (not cluster-name/* only).
          "${replace(aws_msk_serverless_cluster.fraud_events[0].arn, ":cluster/", ":topic/")}/*",
          "arn:aws:kafka:${var.aws_region}:${var.aws_account_id}:topic/${aws_msk_serverless_cluster.fraud_events[0].cluster_uuid}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  count = var.enable_msk && var.enable_bastion ? 1 : 0
  name  = "medcore-bastion"
  role  = aws_iam_role.bastion[0].name
}

resource "aws_instance" "bastion" {
  count = var.enable_msk && var.enable_bastion ? 1 : 0

  ami                         = data.aws_ssm_parameter.bastion_al2023_ami[0].value
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.streaming_public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  key_name                    = aws_key_pair.bastion[0].key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion[0].name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eux
    dnf install -y bind-utils nmap-ncat git python3.11 python3.11-pip
  EOT

  tags = { Name = "medcore-bastion" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "bastion" {
  count  = var.enable_msk && var.enable_bastion ? 1 : 0
  domain = "vpc"

  tags = { Name = "medcore-bastion-eip" }
}

resource "aws_eip_association" "bastion" {
  count         = var.enable_msk && var.enable_bastion ? 1 : 0
  instance_id   = aws_instance.bastion[0].id
  allocation_id = aws_eip.bastion[0].id
}
