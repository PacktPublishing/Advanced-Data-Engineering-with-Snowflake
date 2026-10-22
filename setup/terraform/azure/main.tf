terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "book" {
  name     = "${var.resource_prefix}-rg"
  location = var.azure_location
}

# ---------------------------------------------------------------------------
# Event Hubs Namespace (Standard — exposes Kafka endpoint on port 9093)
# ---------------------------------------------------------------------------
resource "azurerm_eventhub_namespace" "book" {
  name                = "${var.resource_prefix}-ehns"
  location            = azurerm_resource_group.book.location
  resource_group_name = azurerm_resource_group.book.name
  sku                 = "Standard"
  capacity            = 1

  tags = { Chapter = "4" }
}

# ---------------------------------------------------------------------------
# Event Hub (Kafka topic equivalent)
# ---------------------------------------------------------------------------
resource "azurerm_eventhub" "fraud_events" {
  name              = "fraud-events"
  namespace_id      = azurerm_eventhub_namespace.book.id
  partition_count   = 2
  message_retention = 1
}

# ---------------------------------------------------------------------------
# Shared Access Policy with Listen + Send (used by Kafka Connect)
# ---------------------------------------------------------------------------
resource "azurerm_eventhub_authorization_rule" "kafka_connect" {
  name                = "kafka-connect"
  namespace_name      = azurerm_eventhub_namespace.book.name
  eventhub_name       = azurerm_eventhub.fraud_events.name
  resource_group_name = azurerm_resource_group.book.name
  listen              = true
  send                = true
  manage              = false
}
