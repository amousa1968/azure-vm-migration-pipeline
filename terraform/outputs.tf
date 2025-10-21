output "isolation_zone_ready" {
  description = "Indicates if the isolation zone is ready for migration"
  value       = "Isolation zone provisioned successfully in ${azurerm_resource_group.migration_rg.location}"
}

output "network_details" {
  description = "Network configuration details"
  value = {
    vnet_name    = azurerm_virtual_network.migration_vnet.name
    subnet_name  = azurerm_subnet.migration_subnet.name
    address_space = azurerm_virtual_network.migration_vnet.address_space
  }
}

output "security_details" {
  description = "Security configuration details"
  value = {
    nsg_name     = azurerm_network_security_group.migration_nsg.name
    backup_vault = azurerm_recovery_services_vault.migration_vault.name
  }
}

output "monitoring_details" {
  description = "Monitoring configuration details"
  value = {
    log_analytics_workspace = azurerm_log_analytics_workspace.migration_logs.name
    action_group           = azurerm_monitor_action_group.critical_alerts.name
  }
}
