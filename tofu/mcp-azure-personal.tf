# ============================================================================
# mcp-azure-personal permissions
# ============================================================================
# The personal Azure MCP server is intentionally read-oriented for broad
# troubleshooting from tank-operator sessions. Cost Analysis uses separate
# Microsoft.CostManagement and Microsoft.Consumption actions that are not
# covered by ordinary resource-specific grants.

data "azuread_service_principal" "mcp_azure_personal" {
  client_id = "a3508896-9103-4224-afc2-db620011416a"
}

resource "azurerm_role_assignment" "mcp_azure_personal_default_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = data.azuread_service_principal.mcp_azure_personal.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_azure_personal_default_cost_management_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = data.azuread_service_principal.mcp_azure_personal.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_azure_personal_reader" {
  provider             = azurerm.cluster
  scope                = "/subscriptions/${local.cluster_subscription_id}"
  role_definition_name = "Reader"
  principal_id         = data.azuread_service_principal.mcp_azure_personal.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "mcp_azure_personal_cost_management_reader" {
  provider             = azurerm.cluster
  scope                = "/subscriptions/${local.cluster_subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = data.azuread_service_principal.mcp_azure_personal.object_id
  principal_type       = "ServicePrincipal"
}
