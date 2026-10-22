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
  region                   = var.aws_region
  skip_metadata_api_check  = true
  shared_credentials_files = fileexists(pathexpand("~/.aws/credentials")) ? [pathexpand("~/.aws/credentials")] : null
  shared_config_files      = fileexists(pathexpand("~/.aws/config")) ? [pathexpand("~/.aws/config")] : null
}
