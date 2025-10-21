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
