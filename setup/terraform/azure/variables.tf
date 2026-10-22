variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_location" {
  description = "Azure region for Event Hubs resources"
  type        = string
  default     = "canadacentral"
}

variable "resource_prefix" {
  description = "Prefix for all Azure resource names"
  type        = string
  default     = "medcore-book"
}
