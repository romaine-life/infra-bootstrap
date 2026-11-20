# ============================================================================
# nelsong6/openbao CI identity (BAO-15)
# ============================================================================
# nelsong6/openbao (Forgejo only) keeps its store configuration in OpenTofu, run by
# pipeline-templates' tofu suite: a plan on every pull request, an apply on main.
# Both log in to Azure as this identity, which reaches only what that
# configuration reads: its own state blob's container and six named secrets.
# It is not a module.app_org app: that module makes a GitHub repository and grants
# Key Vault Administrator on both subscriptions, and openbao has neither need.
# Its Forgejo trust is in forgejo-ci.tf; its ARM_* Actions variables are set on the
# Forgejo repository, as for every other Forgejo repo.
# ============================================================================

resource "azuread_application" "openbao_ci" {
  display_name = "openbao"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "openbao_ci" {
  client_id = azuread_application.openbao_ci.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# State (nelsontofu/tfstate, key openbao.tfstate). A data role on the container is
# enough only when the backend authenticates with Entra ID, so openbao's
# `backend "azurerm"` sets use_azuread_auth = true; with account-key auth, OpenTofu
# first lists the account's keys, which would need a management role over every
# repository's state.
resource "azurerm_role_assignment" "openbao_ci_tfstate" {
  scope                = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.openbao_ci.object_id
}

# The secrets it reads. Both vaults use Azure RBAC, so each secret gets its own
# Key Vault Secrets User assignment, and no other secret's value is readable.
data "azurerm_key_vault" "auth" {
  name                = "ng6-auth"
  resource_group_name = "auth-rg"
}

locals {
  openbao_ci_vaults = {
    "romaine-kv" = data.azurerm_key_vault.main.id
    "ng6-auth"   = data.azurerm_key_vault.auth.id
  }

  openbao_ci_secrets = {
    "romaine-kv/nas-automation-password"   = data.azurerm_key_vault.main.id
    "romaine-kv/ntfy-home-token"           = data.azurerm_key_vault.main.id
    "romaine-kv/nas-event-logs-password"   = data.azurerm_key_vault.main.id
    "romaine-kv/home-cluster-acme"         = data.azurerm_key_vault.main.id
    "ng6-auth/openbao-oidc-client-secret"  = data.azurerm_key_vault.auth.id
    "ng6-auth/openproject-machine-clients" = data.azurerm_key_vault.auth.id
  }
}

resource "azurerm_role_assignment" "openbao_ci_secret" {
  for_each = local.openbao_ci_secrets

  scope                = "${each.value}/secrets/${split("/", each.key)[1]}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.openbao_ci.object_id
}

# azurerm reads a secret by its vault's resource id, and looks the vault's address up
# with an Azure Resource Manager read of the vault first
# (internal/services/keyvault/client/helpers.go, BaseUriForKeyVault). Reader on the
# vault allows that read: the vault's properties and its secrets' names, never a value.
resource "azurerm_role_assignment" "openbao_ci_vault_reader" {
  for_each = local.openbao_ci_vaults

  scope                = each.value
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.openbao_ci.object_id
}

output "openbao_ci_client_id" {
  value       = azuread_application.openbao_ci.client_id
  description = "Client id of nelsong6/openbao's CI identity, its ARM_CLIENT_ID."
}
