# ============================================================================
# nelsong6/openproject CI identity (OPADMIN-37)
# ============================================================================
# nelsong6/openproject keeps OpenProject's types, statuses and workflows in OpenTofu, run
# by pipeline-templates' tofu suite: a plan on every pull request, an apply on main. Both
# log in to Azure as this identity for state alone: its own state blob's container. It
# signs in to OpenProject with its Forgejo job token, not through Azure, so it reads no
# secret. Like openbao-ci.tf, it is not a module.app_org app (that makes a GitHub
# repository and grants Key Vault Administrator). Its Forgejo trust is in forgejo-ci.tf;
# its ARM_* Actions variables are set on the Forgejo repository.
# ============================================================================

resource "azuread_application" "openproject_ci" {
  display_name = "openproject"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "openproject_ci" {
  client_id = azuread_application.openproject_ci.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# State (nelsontofu/tfstate, key openproject.tfstate). A data role on the container is
# enough because openproject's `backend "azurerm"` sets use_azuread_auth = true, as
# openbao's does (openbao-ci.tf).
resource "azurerm_role_assignment" "openproject_ci_tfstate" {
  scope                = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.openproject_ci.object_id
}

output "openproject_ci_client_id" {
  value       = azuread_application.openproject_ci.client_id
  description = "Client id of nelsong6/openproject's CI identity, its ARM_CLIENT_ID."
}
