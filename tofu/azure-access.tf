# ============================================================================
# Azure access on Nelson's approval (AUT-9)
# ============================================================================
# A home machine asks auth.romaine.life for Azure access (`romaine-auth azure
# request`), Nelson approves it on auth.romaine.life, and while that grant lasts
# auth signs the machine short-lived tokens for this identity: issuer
# https://auth.romaine.life, audience api://AzureADTokenExchange, subject
# `azure-access:approved-grant`. `az login --service-principal --federated-token`
# turns one into Azure access as this identity. auth signs that subject only for
# a machine holding an approved, unexpired, unrevoked grant, so the approval is
# the gate; a token lives ten minutes, and the access token Azure trades it for
# about an hour.
#
# It is a user-assigned managed identity, not an app registration, as tank-
# operator's mcp-azure-personal was. Its roles are the ones that identity held:
# Contributor and Cost Management Reader on this subscription, Key Vault Secrets
# Officer on both subscriptions, data access to the shared Cosmos account, and
# the Azure Kubernetes Service Contributor role on infra-aks; plus the AKS Cluster
# User role, so `az aks get-credentials` works under it.
# ============================================================================

locals {
  azure_access_issuer  = "https://auth.romaine.life"
  azure_access_subject = "azure-access:approved-grant"
}

resource "azurerm_user_assigned_identity" "azure_access" {
  name                = "azure-access"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
}

resource "azurerm_federated_identity_credential" "azure_access" {
  name                = "auth-romaine-approved-grant"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.azure_access.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.azure_access_issuer
  subject             = local.azure_access_subject
}

locals {
  azure_access_roles = {
    workload-contributor = {
      scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      role  = "Contributor"
    }
    workload-cost-reader = {
      scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      role  = "Cost Management Reader"
    }
    workload-keyvault-secrets = {
      scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      role  = "Key Vault Secrets Officer"
    }
    cluster-keyvault-secrets = {
      scope = "/subscriptions/${var.cluster_subscription_id}"
      role  = "Key Vault Secrets Officer"
    }
    aks-contributor = {
      scope = azurerm_kubernetes_cluster.cluster.id
      role  = "Azure Kubernetes Service Contributor Role"
    }
    aks-cluster-user = {
      scope = azurerm_kubernetes_cluster.cluster.id
      role  = "Azure Kubernetes Service Cluster User Role"
    }
  }
}

resource "azurerm_role_assignment" "azure_access" {
  for_each = local.azure_access_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.azure_access.principal_id
  principal_type       = "ServicePrincipal"
}

# Cosmos DB's data plane has its own RBAC; Contributor reaches only the account.
resource "azurerm_cosmosdb_sql_role_assignment" "azure_access" {
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.serverless.name
  # Built-in Data Contributor.
  role_definition_id = "${azurerm_cosmosdb_account.serverless.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = azurerm_user_assigned_identity.azure_access.principal_id
  scope              = azurerm_cosmosdb_account.serverless.id
}

output "azure_access_client_id" {
  description = "Client id of the azure-access identity: auth's azureAccess.clientId (romaine-life/auth k8s/values.yaml)."
  value       = azurerm_user_assigned_identity.azure_access.client_id
}

output "azure_access_tenant_id" {
  description = "Tenant the azure-access identity signs in to: auth's azureAccess.tenantId."
  value       = azurerm_user_assigned_identity.azure_access.tenant_id
}
