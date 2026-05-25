# ============================================================================
# Azure Key Vault
# ============================================================================
# The platform/shared Key Vault is created by the bootstrap script
# (06-keyvault.ps1). App-owned Key Vaults belong in the app repos that own
# those secrets.

data "azurerm_key_vault" "main" {
  name                = "romaine-kv"
  resource_group_name = data.azurerm_resource_group.main.name
}

# Azure config for ExternalDNS workload identity — stored as a JSON
# blob so ExternalSecret can sync it as the azure.json file.
resource "azurerm_key_vault_secret" "external_dns_azure_config" {
  name         = "external-dns-azure-config"
  key_vault_id = data.azurerm_key_vault.main.id
  value = jsonencode({
    tenantId                     = data.azurerm_client_config.current.tenant_id
    subscriptionId               = data.azurerm_client_config.current.subscription_id
    resourceGroup                = data.azurerm_resource_group.main.name
    useWorkloadIdentityExtension = true
  })
}

data "azurerm_key_vault_secret" "github_pat" {
  name         = "github-pat"
  key_vault_id = data.azurerm_key_vault.main.id
}
