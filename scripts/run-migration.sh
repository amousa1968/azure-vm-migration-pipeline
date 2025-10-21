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
