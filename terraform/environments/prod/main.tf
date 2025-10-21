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
