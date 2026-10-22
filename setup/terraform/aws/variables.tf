variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "aws_account_id" {
  description = "Your AWS account ID (12 digits)"
  type        = string
}

variable "bucket_suffix" {
  description = "Unique suffix for the S3 bucket name"
  type        = string
}

# Phase 2 — populate after DESCRIBE EXTERNAL VOLUME in Snowflake
variable "snowflake_ext_vol_iam_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN from DESCRIBE EXTERNAL VOLUME"
  type        = string
  default     = ""
}

variable "snowflake_ext_vol_ext_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from DESCRIBE EXTERNAL VOLUME"
  type        = string
  default     = ""
}

# Phase 2 — populate after DESCRIBE CATALOG INTEGRATION in Snowflake
variable "snowflake_glue_iam_arn" {
  description = "GLUE_AWS_IAM_USER_ARN from DESCRIBE CATALOG INTEGRATION"
  type        = string
  default     = ""
}

variable "snowflake_glue_ext_id" {
  description = "GLUE_AWS_EXTERNAL_ID from DESCRIBE CATALOG INTEGRATION"
  type        = string
  default     = ""
}

variable "snowflake_s3tables_iam_arn" {
  description = "S3TABLES IAM ARN from DESCRIBE CATALOG INTEGRATION (S3 Tables)"
  type        = string
  default     = ""
}

variable "snowflake_s3tables_ext_id" {
  description = "S3TABLES external ID from DESCRIBE CATALOG INTEGRATION (S3 Tables)"
  type        = string
  default     = ""
}

# Phase 2 — populate after DESCRIBE STORAGE INTEGRATION lake_int (Ch.3 / Ch.8)
variable "snowflake_stage_iam_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN from DESCRIBE INTEGRATION lake_int"
  type        = string
  default     = ""
}

variable "snowflake_stage_ext_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from DESCRIBE INTEGRATION lake_int"
  type        = string
  default     = ""
}

# Chapter 4 — streaming infrastructure (optional, default off)
variable "enable_msk" {
  description = "Create MSK Serverless cluster + VPC for Chapter 4 Kafka exercises"
  type        = bool
  default     = false
}

variable "enable_kinesis" {
  description = "Create Kinesis Data Stream + IAM user for Chapter 4 OpenFlow Kinesis exercise"
  type        = bool
  default     = false
}

variable "kinesis_application_name" {
  description = "Openflow Kinesis connector Application Name; also its DynamoDB checkpoint table name"
  type        = string
  default     = "techflow_fraud_events"
}

# WireGuard into streaming VPC (ECS on EC2 — requires enable_msk)
variable "enable_vpn" {
  description = "ECS (EC2) WireGuard in the MSK VPC; UDP only from vpn_admin_cidr"
  type        = bool
  default     = false
}

variable "vpn_admin_cidr" {
  description = "CIDR allowed to send WireGuard UDP to the VPN host (use your public IP /32). Required when enable_vpn is true."
  type        = string
  default     = null
}

variable "vpn_wireguard_port" {
  type    = number
  default = 51820
}

variable "vpn_peer_count" {
  description = "linuxserver/wireguard PEERS (QR/config files generated under /config on EFS)"
  type        = number
  default     = 1
}

variable "vpn_ecs_instance_type" {
  description = "x86 recommended (linuxserver/wireguard image)"
  type        = string
  default     = "t3.micro"
}

# SSH bastion in MSK VPC (simple Mac workflow: ssh ec2-user@eip; run MSK tools there)
variable "enable_bastion" {
  description = "EC2 in public subnet; SSH from bastion_ssh_cidr only. Replaces laptop VPN/DNS for MSK."
  type        = bool
  default     = false
}

variable "bastion_ssh_cidr" {
  description = "Your public IPv4 /32 allowed to SSH (tcp/22) to the bastion. Required when enable_bastion is true."
  type        = string
  default     = null
}

variable "bastion_ssh_public_key" {
  description = "Contents of your Mac ~/.ssh/id_ed25519.pub or id_rsa.pub (required when enable_bastion is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

# MSK Connect — managed Kafka Connect for Snowflake sink (requires enable_msk)
variable "enable_msk_connect" {
  description = "Deploy MSK Connect with Snowflake Kafka Connector (requires enable_msk = true)"
  type        = bool
  default     = false
}

variable "snowflake_account_url" {
  description = "Snowflake account URL for the Kafka Connector (e.g. xy12345.snowflakecomputing.com)"
  type        = string
  default     = ""
}

variable "snowflake_streaming_user" {
  description = "Snowflake username for Snowpipe Streaming ingestion (key-pair auth)"
  type        = string
  default     = ""
}

variable "snowflake_private_key_pem" {
  description = "RSA private key content (PEM body, no header/footer) for Snowflake key-pair auth"
  type        = string
  default     = ""
  sensitive   = true
}

variable "msk_connect_plugin_local_path" {
  description = "Local path to the Snowflake Kafka Connector ZIP for MSK Connect custom plugin"
  type        = string
  default     = ""
}
