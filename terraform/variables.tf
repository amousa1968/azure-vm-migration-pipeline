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
