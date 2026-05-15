# ============================================================================
# Shared Infrastructure - Outputs
# ============================================================================
# These outputs are consumed by app repositories via remote state data source.
# App repos reference these values to deploy resources in the shared infrastructure.
# ============================================================================

# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  value       = data.azurerm_resource_group.main.name
  description = "Name of the shared resource group for all applications"
}

output "resource_group_location" {
  value       = data.azurerm_resource_group.main.location
  description = "Azure region where resources are deployed"
}

output "resource_group_id" {
  value       = data.azurerm_resource_group.main.id
  description = "Resource ID of the shared resource group"
}

# ============================================================================
# DNS Zone Outputs
# ============================================================================

output "dns_zone_name" {
  value       = azurerm_dns_zone.main.name
  description = "Name of the shared DNS zone (e.g., romaine.life)"
}

output "dns_zone_id" {
  value       = azurerm_dns_zone.main.id
  description = "Resource ID of the shared DNS zone"
}

# ============================================================================
# Cosmos DB Outputs
# ============================================================================

output "cosmos_db_account_name" {
  value       = azurerm_cosmosdb_account.serverless.name
  description = "Name of the shared Cosmos DB account"
}

output "cosmos_db_account_id" {
  value       = azurerm_cosmosdb_account.serverless.id
  description = "Resource ID of the shared Cosmos DB account"
}

# ============================================================================
# App Configuration Outputs
# ============================================================================

output "azure_app_config_endpoint" {
  value       = azurerm_app_configuration.main.endpoint
  description = "Endpoint URL for the shared Azure App Configuration store"
}

output "azure_app_config_resource_id" {
  value       = azurerm_app_configuration.main.id
  description = "Resource ID of the shared Azure App Configuration store"
}

# ============================================================================
# Azure Identity Outputs
# ============================================================================

output "arm_subscription_id" {
  value       = data.azurerm_client_config.current.subscription_id
  description = "Azure subscription ID"
}

output "arm_tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Azure tenant ID"
}

# ============================================================================
# AKS Outputs
# ============================================================================

output "aks_cluster_name" {
  value       = local.active_aks_cluster_name
  description = "Name of the AKS cluster"
}

output "aks_resource_group_name" {
  value       = local.cluster_resource_group_name
  description = "Resource group containing the AKS cluster"
}

output "aks_cluster_id" {
  value       = local.active_aks_cluster_id
  description = "Resource ID of the AKS cluster"
}

output "aks_oidc_issuer_url" {
  value       = local.active_aks_oidc_issuer_url
  description = "OIDC issuer URL for workload identity federation"
}

# ============================================================================
# Container Registry Outputs
# ============================================================================

output "acr_name" {
  value       = azurerm_container_registry.main.name
  description = "Name of the Azure Container Registry"
}

output "acr_login_server" {
  value       = azurerm_container_registry.main.login_server
  description = "Login server URL for the Azure Container Registry (e.g., romainecr.azurecr.io)"
}

# ============================================================================
# Shared Identity Outputs
# ============================================================================

output "shared_identity_client_id" {
  value       = azurerm_user_assigned_identity.shared.client_id
  description = "Client ID of the shared managed identity (used for workload identity annotations on K8s service accounts)"
}
