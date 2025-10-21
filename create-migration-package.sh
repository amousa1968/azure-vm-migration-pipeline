#!/bin/bash

# Azure VM Migration Pipeline Package Creator
# Complete package generation script

set -e

PACKAGE_NAME="azure-vm-migration-pipeline"
VERSION="1.0.0"
ZIP_FILE="${PACKAGE_NAME}-${VERSION}.zip"
TEMP_DIR="temp_package_$$"

echo "Creating Azure VM Migration Pipeline Package v${VERSION}"
echo "======================================================="

# Clean up any existing files
rm -rf "${TEMP_DIR}" "${ZIP_FILE}" 2>/dev/null || true

# Create directory structure
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

echo "Creating directory structure..."
mkdir -p terraform/{modules/vm-import,environments/prod,modules/vm-scale-set}
mkdir -p ansible/{playbooks,roles/security_hardening/{tasks,handlers},inventory,group_vars,templates}
mkdir -p github-workflows scripts docs

echo "Creating Terraform configuration files..."

# terraform/main.tf
cat > terraform/main.tf << 'EOF'
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
EOF

# terraform/variables.tf
cat > terraform/variables.tf << 'EOF'
variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "East US"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the migration subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ip_range" {
  description = "IP range allowed to access the migration environment"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "VM Migration"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

variable "vms_to_migrate" {
  description = "List of VMs to migrate"
  type = list(object({
    name          = string
    source_vm_id  = string
    os_type       = string
    tier          = string
  }))
  default = []
}

variable "alert_email" {
  description = "Email address for critical alerts"
  type        = string
  default     = "admin@company.com"
}
EOF

# terraform/outputs.tf
cat > terraform/outputs.tf << 'EOF'
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
EOF

# Create environment-specific files
cat > terraform/environments/prod/main.tf << 'EOF'
module "migration_infrastructure" {
  source = "../.."

  environment    = "prod"
  location       = "East US 2"
  alert_email    = "prod-alerts@company.com"
  allowed_ip_range = "10.0.0.0/8"

  tags = {
    Environment = "production"
    Criticality = "high"
    Backup      = "enabled"
    Monitoring  = "enabled"
  }
}
EOF

cat > terraform/environments/prod/prod.tfvars.example << 'EOF'
# Production Environment Configuration
environment = "prod"
location = "East US 2"

# Network Configuration
vnet_address_space = "10.0.0.0/16"
subnet_address_prefix = "10.0.1.0/24"
allowed_ip_range = "10.0.0.0/8"

# Monitoring
alert_email = "prod-alerts@company.com"

# Tags
tags = {
  Environment = "production"
  Project     = "VM Migration"
  CostCenter  = "IT-123"
  SLA         = "99.9%"
}
EOF

echo "Creating Ansible playbooks and roles..."

# ansible/playbooks/azure-migrate-orchestration.yml
cat > ansible/playbooks/azure-migrate-orchestration.yml << 'EOF'
---
- name: Azure Migrate VM Migration Orchestration
  hosts: localhost
  gather_facts: false
  vars:
    azure_subscription_id: "{{ azure_subscription_id }}"
    azure_tenant_id: "{{ azure_tenant_id }}"
    azure_client_id: "{{ azure_client_id }}"
    azure_client_secret: "{{ azure_client_secret }}"
    resource_group: "{{ resource_group }}"
    migration_project: "{{ migration_project }}"

  tasks:
    - name: Verify Azure credentials
      azure_rm_resource_info:
        resource_group: "{{ resource_group }}"
        provider: "Microsoft.Resources"
        resource_type: "resourceGroups"
      register: rg_info

    - name: Display migration readiness
      debug:
        msg: "Azure environment is ready for migration"

    - name: Generate Terraform import configuration
      template:
        src: terraform_import.j2
        dest: "/tmp/terraform_import_{{ inventory_hostname }}.tf"
      vars:
        vm_name: "{{ inventory_hostname }}"
        resource_group: "{{ resource_group }}"

    - name: Create migration readiness report
      template:
        src: migration_report.j2
        dest: "/tmp/migration_readiness_{{ inventory_hostname }}.md"
EOF

# ansible/playbooks/day2-operations.yml
cat > ansible/playbooks/day2-operations.yml << 'EOF'
---
- name: Day 2 Operations Configuration
  hosts: migrated_vms
  become: yes
  gather_facts: yes
  vars:
    log_analytics_workspace_id: "{{ log_analytics_workspace_id }}"
    log_analytics_key: "{{ log_analytics_key }}"

  tasks:
    - name: Install Azure Monitor Agent (Windows)
      win_package:
        path: https://go.microsoft.com/fwlink/?linkid=2190492
        product_id: "AzureMonitorAgent"
        state: present
      when: ansible_os_family == "Windows"

    - name: Install Azure Monitor Agent (Linux)
      apt:
        name: azmonitoragent
        state: present
        update_cache: yes
      when: ansible_os_family == "Debian"

    - name: Configure automatic updates (Windows)
      win_updates:
        category_names:
          - SecurityUpdates
          - CriticalUpdates
          - UpdateRollups
        state: installed
      when: ansible_os_family == "Windows"

    - name: Configure automatic updates (Linux)
      apt:
        upgrade: dist
        update_cache: yes
        autoremove: yes
        autoclean: yes
      when: ansible_os_family == "Debian"

    - name: Install and configure baseline security tools
      include_role:
        name: security_hardening

    - name: Verify all required services are running
      service:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop: "{{ critical_services | default([]) }}"
      ignore_errors: yes

    - name: Create success flag file
      file:
        path: /etc/migration_complete
        state: touch
        mode: '0644'
EOF

# Create security hardening role
cat > ansible/roles/security_hardening/tasks/main.yml << 'EOF'
---
- name: Apply CIS benchmarks for Windows
  block:
    - name: Disable SMBv1
      win_command: Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

    - name: Enable Windows Firewall
      win_command: Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

    - name: Set password policy
      win_command: |
        net accounts /minpwlen:14
        net accounts /maxpwage:60

    - name: Disable guest account
      win_command: net user guest /active:no

  when: ansible_os_family == "Windows"

- name: Apply CIS benchmarks for Linux
  block:
    - name: Ensure password expiration is 90 days
      lineinfile:
        path: /etc/login.defs
        regexp: '^PASS_MAX_DAYS'
        line: 'PASS_MAX_DAYS 90'

    - name: Ensure password change minimum days is 7
      lineinfile:
        path: /etc/login.defs
        regexp: '^PASS_MIN_DAYS'
        line: 'PASS_MIN_DAYS 7'

    - name: Disable root login
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PermitRootLogin'
        line: 'PermitRootLogin no'
      notify: restart sshd

  when: ansible_os_family == "Linux"
EOF

cat > ansible/roles/security_hardening/handlers/main.yml << 'EOF'
---
- name: restart sshd
  service:
    name: sshd
    state: restarted
EOF

# Create inventory file
cat > ansible/inventory/production_hosts << 'EOF'
[migrated_vms]
# Add your migrated VM IPs or hostnames here
# vm1 ansible_host=10.0.1.4 ansible_user=admin
# vm2 ansible_host=10.0.1.5 ansible_user=admin

[migration_controllers]
localhost ansible_connection=local
EOF

echo "Creating GitHub workflows..."

# github-workflows/migration-pipeline.yml
cat > github-workflows/migration-pipeline.yml << 'EOF'
name: VM Migration Pipeline

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        default: 'prod'
        type: choice
        options:
        - dev
        - staging
        - prod
      migration_phase:
        description: 'Migration phase to execute'
        required: true
        default: 'all'
        type: choice
        options:
        - environment-provisioning
        - vm-replication
        - cutover
        - day2-operations
        - all

env:
  TERRAFORM_VERSION: '1.5.0'
  ANSIBLE_VERSION: '2.13.0'

jobs:
  environment-provisioning:
    if: contains(github.event.inputs.migration_phase, 'environment-provisioning') || contains(github.event.inputs.migration_phase, 'all')
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: ${{ env.TERRAFORM_VERSION }}

    - name: Terraform Init
      run: |
        cd terraform/environments/${{ github.event.inputs.environment }}
        terraform init

    - name: Terraform Plan
      run: |
        cd terraform/environments/${{ github.event.inputs.environment }}
        terraform plan -var-file="${{ github.event.inputs.environment }}.tfvars"

    - name: Terraform Apply
      run: |
        cd terraform/environments/${{ github.event.inputs.environment }}
        terraform apply -auto-approve

    - name: Update outputs
      run: |
        cd terraform/environments/${{ github.event.inputs.environment }}
        terraform output -json > ../../outputs/${{ github.event.inputs.environment }}.json

  day2-operations:
    if: contains(github.event.inputs.migration_phase, 'day2-operations') || contains(github.event.inputs.migration_phase, 'all')
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}

    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'

    - name: Install Ansible
      run: |
        pip install ansible==${{ env.ANSIBLE_VERSION }}

    - name: Configure Day 2 Operations
      run: |
        cd ansible/playbooks
        ansible-playbook day2-operations.yml -i ../inventory/production_hosts

  notify-completion:
    if: always()
    needs: [environment-provisioning, day2-operations]
    runs-on: ubuntu-latest
    
    steps:
    - name: Notify completion
      run: |
        echo "Migration pipeline for ${{ github.event.inputs.environment }} completed"
EOF

echo "Creating utility scripts..."

# scripts/update-dns-records.sh
cat > scripts/update-dns-records.sh << 'EOF'
#!/bin/bash

# Script to update DNS records after cutover
set -e

ENVIRONMENT=${1:-prod}
RESOURCE_GROUP="migration-isolation-zone-${ENVIRONMENT}"
DNS_ZONE="company.com"
DNS_RESOURCE_GROUP="dns-rg"

echo "Updating DNS records for environment: $ENVIRONMENT"

# Get public IPs of migrated VMs
IPS=$(az vm list-ip-addresses --resource-group $RESOURCE_GROUP --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)

for IP in $IPS; do
    VM_NAME=$(az vm list --resource-group $RESOURCE_GROUP --query "[?('$IP' in network.publicIpAddresses[0].ipAddress)].name" -o tsv)
    
    if [ ! -z "$VM_NAME" ]; then
        echo "Updating DNS record for $VM_NAME to $IP"
        
        # Update DNS record
        az network dns record-set a update \
            --resource-group $DNS_RESOURCE_GROUP \
            --zone-name $DNS_ZONE \
            --name $VM_NAME \
            --set aRecords="[{'ipv4Address': '$IP'}]"
    fi
done

echo "DNS update completed successfully"
EOF

# scripts/validate-migration.sh
cat > scripts/validate-migration.sh << 'EOF'
#!/bin/bash

# Migration validation script
set -e

ENVIRONMENT=${1:-prod}
RESOURCE_GROUP="migration-isolation-zone-${ENVIRONMENT}"

echo "Validating migration for environment: $ENVIRONMENT"

# Check VM status
echo "Checking VM status..."
VMS=$(az vm list --resource-group $RESOURCE_GROUP --query "[].name" -o tsv)

for VM in $VMS; do
    STATUS=$(az vm get-instance-view --name $VM --resource-group $RESOURCE_GROUP --query "instanceView.statuses[?contains(code, 'PowerState')].displayStatus" -o tsv)
    echo "VM: $VM - Status: $STATUS"
    
    if [[ $STATUS != "VM running" ]]; then
        echo "ERROR: VM $VM is not running"
        exit 1
    fi
done

echo "Migration validation completed successfully"
EOF

# scripts/setup-environment.sh
cat > scripts/setup-environment.sh << 'EOF'
#!/bin/bash

# Environment setup script for Azure VM Migration
set -e

echo "Azure VM Migration Pipeline Setup"
echo "=================================="

# Check prerequisites
command -v az >/dev/null 2>&1 || { echo "Azure CLI is required but not installed. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed. Aborting."; exit 1; }
command -v ansible >/dev/null 2>&1 || { echo "Ansible is required but not installed. Aborting."; exit 1; }

echo "Prerequisites verified."

# Login to Azure
echo "Please login to Azure..."
az login

# Set subscription
read -p "Enter Azure Subscription ID: " SUBSCRIPTION_ID
az account set --subscription $SUBSCRIPTION_ID

# Create terraform backend resources
echo "Creating Terraform backend resources..."
az group create --name tfstate-rg --location eastus
az storage account create --resource-group tfstate-rg --name tfstatestorage --sku Standard_LRS --encryption-services blob
az storage container create --name tfstate --account-name tfstatestorage

echo "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Update terraform/environments/prod/prod.tfvars with your configuration"
echo "2. Configure GitHub secrets for your repository"
echo "3. Run: terraform init in terraform/environments/prod/"
echo "4. Execute: terraform plan && terraform apply"
EOF

# scripts/run-migration.sh
cat > scripts/run-migration.sh << 'EOF'
#!/bin/bash

# Main migration execution script
set -e

ENVIRONMENT=${1:-prod}
PHASE=${2:-all}

echo "Starting migration for environment: $ENVIRONMENT, phase: $PHASE"

case $PHASE in
    "environment-provisioning")
        echo "Executing environment provisioning..."
        cd terraform/environments/$ENVIRONMENT
        terraform init
        terraform plan -var-file="$ENVIRONMENT.tfvars"
        terraform apply -auto-approve -var-file="$ENVIRONMENT.tfvars"
        ;;
    "day2-operations")
        echo "Executing Day 2 operations..."
        cd ansible/playbooks
        ansible-playbook day2-operations.yml -i ../inventory/production_hosts
        ;;
    "all")
        echo "Executing complete migration pipeline..."
        ./scripts/setup-environment.sh
        cd terraform/environments/$ENVIRONMENT
        terraform init
        terraform apply -auto-approve -var-file="$ENVIRONMENT.tfvars"
        cd ../../..
        ansible-playbook ansible/playbooks/day2-operations.yml -i ansible/inventory/production_hosts
        ;;
    *)
        echo "Unknown phase: $PHASE"
        echo "Available phases: environment-provisioning, day2-operations, all"
        exit 1
        ;;
esac

echo "Migration phase $PHASE completed successfully"
EOF

echo "Creating documentation..."

# docs/README.md
cat > docs/README.md << 'EOF'
# Azure VM Migration Pipeline

A comprehensive automated pipeline for migrating virtual machines from on-premises VMware to Azure cloud platform.

## Features

- **Automated Migration**: End-to-end automation using Terraform and Ansible
- **Multi-Phase Pipeline**: Structured migration process
- **Day 2 Operations**: Automated configuration of monitoring, backup, and security
- **Infrastructure as Code**: Complete Terraform management of Azure resources
- **CI/CD Integration**: GitHub Actions for pipeline orchestration
- **Production Ready**: Includes monitoring, backup, and security configurations

## Architecture

The migration pipeline consists of multiple phases:

1. **Environment Provisioning** - Terraform creates isolation zone in Azure
2. **VM Migration** - Azure Migrate replicates VMs (manual step)
3. **Post-Migration Setup** - Import VMs into Terraform management  
4. **Cutover Execution** - Stop replication and switch to Azure environment
5. **Day-2 Operations** - Configure monitoring, backup, and security

## Quick Start

1. **Setup Environment**
   ```bash
   chmod +x scripts/setup-environment.sh
   ./scripts/setup-environment.sh