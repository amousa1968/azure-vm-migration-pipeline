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

## File Structure
text
azure-vm-migration-pipeline/
**├── terraform/**                 # Infrastructure as Code
**├── ansible/**                   # Configuration management
├── github-workflows/          # CI/CD pipelines
├── scripts/                   # Utility scripts
└── docs/                      # Documentation
