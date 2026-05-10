# ============================================================================
# Loki log storage and workload identity
# ============================================================================
# Loki uses Azure Blob Storage for chunks and ruler data, authenticated from
# AKS with workload identity. The Kubernetes ServiceAccount subject must stay
# aligned with k8s/loki/values.yaml: system:serviceaccount:loki:loki.
# ============================================================================

resource "azurerm_storage_account" "loki" {
  name                     = "romainelokilogs"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "loki" {
  for_each = toset([
    "loki-chunks",
    "loki-ruler",
    "loki-admin",
  ])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.loki.id
  container_access_type = "private"
}

resource "azurerm_user_assigned_identity" "loki" {
  name                = "loki-identity"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
}

resource "azurerm_role_assignment" "loki_storage_blob_contributor" {
  scope                = azurerm_storage_account.loki.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.loki.principal_id
}

resource "azurerm_federated_identity_credential" "loki" {
  count               = local.cluster_uses_dedicated_subscription ? 0 : 1
  name                = "aks-loki"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.loki.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:loki:loki"
}

resource "azurerm_federated_identity_credential" "cluster_loki" {
  count               = local.cluster_uses_dedicated_subscription ? 1 : 0
  name                = "aks-cluster-loki"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.loki.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:loki:loki"
}

resource "github_actions_variable" "loki_identity_client_id" {
  repository    = "infra-bootstrap"
  variable_name = "LOKI_IDENTITY_CLIENT_ID"
  value         = azurerm_user_assigned_identity.loki.client_id
}

output "loki_storage_account_name" {
  value       = azurerm_storage_account.loki.name
  description = "Storage account used by Loki for Azure Blob object storage."
}

output "loki_identity_client_id" {
  value       = azurerm_user_assigned_identity.loki.client_id
  description = "Client ID for loki-identity. Pin into k8s/loki/values.yaml serviceAccount annotations."
}
