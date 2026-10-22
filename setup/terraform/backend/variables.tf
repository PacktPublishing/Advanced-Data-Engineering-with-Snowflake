variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "bucket_suffix" {
  description = "Unique suffix for the tfstate bucket name (e.g. your initials + random digits)"
  type        = string
}
