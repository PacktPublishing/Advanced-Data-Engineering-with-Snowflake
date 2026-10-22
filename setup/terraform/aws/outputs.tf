output "s3_bucket_name" {
  value = aws_s3_bucket.medcore_lakehouse.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.medcore_lakehouse.arn
}

output "snowflake_iceberg_role_arn" {
  value = aws_iam_role.snowflake_iceberg_role.arn
}

output "snowflake_glue_role_arn" {
  value = aws_iam_role.snowflake_glue_role.arn
}

output "snowflake_s3tables_role_arn" {
  value = aws_iam_role.snowflake_s3tables_role.arn
}

output "snowflake_stage_role_arn" {
  value = aws_iam_role.snowflake_stage_role.arn
}

output "glue_database_name" {
  value = aws_glue_catalog_database.clinical_research.name
}

output "s3tables_table_bucket_arn" {
  value = aws_s3tables_table_bucket.medcore.arn
}

# Chapter 4 — MSK Serverless
output "msk_bootstrap_brokers" {
  value       = var.enable_msk ? aws_msk_serverless_cluster.fraud_events[0].cluster_uuid : null
  description = "MSK Serverless cluster UUID (use bootstrap_brokers_sasl_iam from aws_msk_serverless_cluster data)"
}

output "msk_bootstrap_brokers_sasl_iam" {
  value = var.enable_msk ? aws_msk_serverless_cluster.fraud_events[0].bootstrap_brokers_sasl_iam : null
}

# Chapter 4 — Kinesis
output "kinesis_stream_arn" {
  value = var.enable_kinesis ? aws_kinesis_stream.fraud_events[0].arn : null
}

output "kinesis_stream_name" {
  value = var.enable_kinesis ? aws_kinesis_stream.fraud_events[0].name : null
}

output "kinesis_connector_access_key_id" {
  value     = var.enable_kinesis ? aws_iam_access_key.kinesis_connector[0].id : null
  sensitive = true
}

output "kinesis_connector_secret_access_key" {
  value     = var.enable_kinesis ? aws_iam_access_key.kinesis_connector[0].secret : null
  sensitive = true
}

# Chapter 4 — WireGuard (ECS on EC2)
output "vpn_ecs_cluster_name" {
  value       = var.enable_msk && var.enable_vpn ? aws_ecs_cluster.vpn[0].name : null
  description = "ECS cluster running WireGuard"
}

output "vpn_wireguard_public_ip" {
  value       = var.enable_msk && var.enable_vpn ? try(data.aws_instances.vpn_ecs[0].public_ips[0], null) : null
  description = "VPN server public IP (WireGuard). Re-run apply or refresh if null until instance is running."
}

output "vpn_wireguard_admin_cidr" {
  value       = var.enable_msk && var.enable_vpn ? var.vpn_admin_cidr : null
  description = "Security group allows WireGuard UDP only from this CIDR"
}

output "vpn_wireguard_client_config_hint" {
  value = var.enable_msk && var.enable_vpn ? join(" ", [
    "Peer configs live on EFS under peer1/peer2…;",
    "easiest: SSM to the ECS instance (Name=medcore-vpn-ecs),",
    "sudo docker ps, docker cp <container>:/config/peer1/peer1.conf .",
    "or mount EFS. CloudWatch: /ecs/medcore-wireguard"
  ]) : null
}

# Chapter 4 — SSH bastion (recommended vs WireGuard on Mac)
output "bastion_public_ip" {
  value       = var.enable_msk && var.enable_bastion ? aws_eip.bastion[0].public_ip : null
  description = "Elastic IP; SSH from bastion_ssh_cidr only"
}

output "bastion_ssh_example" {
  value       = var.enable_msk && var.enable_bastion ? "ssh -i ~/.ssh/id_rsa ec2-user@${aws_eip.bastion[0].public_ip}" : null
  description = "Adjust -i to the private key that matches bastion_ssh_public_key (id_rsa, id_ed25519, etc.)"
}

# Chapter 4 — MSK Connect (managed Kafka Connect for Snowflake sink)
output "msk_connect_connector_arn" {
  value       = var.enable_msk && var.enable_msk_connect ? aws_mskconnect_connector.snowflake_fraud_events[0].arn : null
  description = "ARN of the MSK Connect Snowflake sink connector"
}

output "msk_connect_connector_state" {
  value       = var.enable_msk && var.enable_msk_connect ? aws_mskconnect_connector.snowflake_fraud_events[0].version : null
  description = "Connector version (refresh to check state transitions)"
}

output "msk_connect_log_group" {
  value       = var.enable_msk && var.enable_msk_connect ? aws_cloudwatch_log_group.msk_connect[0].name : null
  description = "CloudWatch log group for MSK Connect worker logs"
}
