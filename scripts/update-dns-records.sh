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
