terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Resource Group for Isolation Zone
resource "azurerm_resource_group" "migration_rg" {
  name     = "migration-isolation-zone-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Network Security Group for Isolation Zone
resource "azurerm_network_security_group" "migration_nsg" {
  name                = "migration-nsg-${var.environment}"
  location            = azurerm_resource_group.migration_rg.location
  resource_group_name = azurerm_resource_group.migration_rg.name
  tags                = var.tags

  security_rule {
    name                       = "allow-rdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.allowed_ip_range
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ip_range
    destination_address_prefix = "*"
  }
}

# Virtual Network for Isolation Zone
resource "azurerm_virtual_network" "migration_vnet" {
  name                = "migration-vnet-${var.environment}"
  location            = azurerm_resource_group.migration_rg.location
  resource_group_name = azurerm_resource_group.migration_rg.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# Subnet for migrated VMs
resource "azurerm_subnet" "migration_subnet" {
  name                 = "migration-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.migration_rg.name
  virtual_network_name = azurerm_virtual_network.migration_vnet.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "migration_nsg_assoc" {
  subnet_id                 = azurerm_subnet.migration_subnet.id
  network_security_group_id = azurerm_network_security_group.migration_nsg.id
}

# Storage Account for VM diagnostics
resource "azurerm_storage_account" "migration_diag" {
  name                     = "migrationdiag${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.migration_rg.name
  location                 = azurerm_resource_group.migration_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

# Random string for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "migration_logs" {
  name                = "migration-logs-${var.environment}"
  location            = azurerm_resource_group.migration_rg.location
  resource_group_name = azurerm_resource_group.migration_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Recovery Services Vault for backups
resource "azurerm_recovery_services_vault" "migration_vault" {
  name                = "migration-vault-${var.environment}"
  location            = azurerm_resource_group.migration_rg.location
  resource_group_name = azurerm_resource_group.migration_rg.name
  sku                 = "Standard"
  tags                = var.tags
}

# Azure Backup Policy
resource "azurerm_backup_policy_vm" "migration_backup" {
  name                = "migration-backup-policy-${var.environment}"
  resource_group_name = azurerm_resource_group.migration_rg.name
  recovery_vault_name = azurerm_recovery_services_vault.migration_vault.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }
}

# Monitor Action Group for alerts
resource "azurerm_monitor_action_group" "critical_alerts" {
  name                = "critical-alerts-${var.environment}"
  resource_group_name = azurerm_resource_group.migration_rg.name
  short_name          = "critical"

  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }
}

output "resource_group_name" {
  value = azurerm_resource_group.migration_rg.name
}

output "vnet_name" {
  value = azurerm_virtual_network.migration_vnet.name
}

output "subnet_name" {
  value = azurerm_subnet.migration_subnet.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.migration_logs.workspace_id
}
