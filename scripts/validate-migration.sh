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
