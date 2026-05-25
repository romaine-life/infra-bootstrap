# ============================================================================
# Platform-owned Key Vaults
# ============================================================================
# These services are owned by infra-bootstrap rather than an app repo, so their
# dedicated runtime vaults live here. The legacy shared `romaine-kv` stays in
# place for bootstrap/manual secrets and consumers that have not moved yet.

locals {
  platform_key_vaults = toset([
    "argocd",
    "external-dns",
    "nats",
  ])
}

resource "azurerm_key_vault" "platform" {
  for_each = local.platform_key_vaults

  name                       = "ng6-${each.key}"
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = data.azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7

  tags = {
    app       = each.key
    managedBy = "infra-bootstrap"
    purpose   = "platform-secrets"
  }
}

resource "azurerm_role_assignment" "platform_external_secrets_keyvault" {
  for_each = azurerm_key_vault.platform

  scope                = each.value.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.shared.principal_id
}

resource "azurerm_key_vault_secret" "external_dns_azure_config_app" {
  name         = "external-dns-azure-config"
  key_vault_id = azurerm_key_vault.platform["external-dns"].id
  value = jsonencode({
    tenantId                     = data.azurerm_client_config.current.tenant_id
    subscriptionId               = data.azurerm_client_config.current.subscription_id
    resourceGroup                = data.azurerm_resource_group.main.name
    useWorkloadIdentityExtension = true
  })
}

resource "azurerm_key_vault_secret" "argocd_oidc_client_id_app" {
  name         = "argocd-oidc-client-id"
  value        = azuread_application.argocd.client_id
  key_vault_id = azurerm_key_vault.platform["argocd"].id
}

resource "azurerm_key_vault_secret" "argocd_oidc_client_secret_app" {
  name         = "argocd-oidc-client-secret"
  value        = azuread_application_password.argocd.value
  key_vault_id = azurerm_key_vault.platform["argocd"].id
}
