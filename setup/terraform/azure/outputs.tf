output "eventhub_namespace" {
  value = azurerm_eventhub_namespace.book.name
}

output "eventhub_kafka_endpoint" {
  value       = "${azurerm_eventhub_namespace.book.name}.servicebus.windows.net:9093"
  description = "Use as bootstrap.servers in Kafka Connect config"
}

output "eventhub_connection_string" {
  value     = azurerm_eventhub_authorization_rule.kafka_connect.primary_connection_string
  sensitive = true
}

output "eventhub_name" {
  value = azurerm_eventhub.fraud_events.name
}
