# ============================================================================
# Azure Kubernetes Service (AKS)
# ============================================================================
# Shared AKS cluster replacing Azure Container Apps. Each app gets its own
# Deployment instead of sharing a single always-on API. Ingress replaces SWA.
# ExternalSecrets replaces direct Key Vault references.
#
# Workload identity is enabled so pods can assume managed identities via
# federated credentials (see shared_workload below).
# ============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  count = local.cluster_uses_dedicated_subscription ? 0 : 1

  name                = "infra-aks"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  dns_prefix          = "infra-aks"

  # Free tier — no SLA, no cost for the control plane
  sku_tier = "Free"

  # Workload identity + OIDC issuer — required for pods to assume
  # managed identities via federated credentials
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Automatic patch upgrades for security fixes
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Cluster identity for managing Azure resources (load balancers, disks).
  # Separate from workload identity used by pods.
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name            = "system"
    vm_size         = "Standard_B2s_v2"
    node_count      = 2
    os_disk_size_gb = 128
    vnet_subnet_id  = azurerm_subnet.aks_nodes.id

    temporary_name_for_rotation = "tmp"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }
}

resource "azurerm_kubernetes_cluster" "cluster" {
  provider = azurerm.cluster
  count    = local.cluster_uses_dedicated_subscription ? 1 : 0

  name                = "infra-aks"
  resource_group_name = local.cluster_resource_group_name
  location            = local.cluster_resource_group_location
  dns_prefix          = "infra-aks"

  sku_tier = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name            = "system"
    vm_size         = "Standard_B2s_v2"
    node_count      = 2
    os_disk_size_gb = 128
    vnet_subnet_id  = azurerm_subnet.cluster_aks_nodes[0].id

    temporary_name_for_rotation = "tmp"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }
}

# Allows the guarded mcp-azure-admin server to use AKS Run Command against the
# dedicated migration cluster without granting write access to the whole subscription.
resource "azurerm_role_assignment" "mcp_azure_admin_cluster_contributor" {
  provider = azurerm.cluster
  count    = local.cluster_uses_dedicated_subscription ? 1 : 0

  scope                = azurerm_kubernetes_cluster.cluster[0].id
  role_definition_name = "Contributor"
  principal_id         = "d63582e4-a494-4f84-b1d2-ae74e125a8ed"
  principal_type       = "ServicePrincipal"
}

# ============================================================================
# Workload Identity — Federated Credential for Shared Identity
# ============================================================================
# Bridges the existing infra-shared-identity (which already has Cosmos DB,
# App Config, Key Vault, and Storage roles) to the AKS OIDC issuer.
# Pods using the "infra-shared" service account in the "default" namespace
# can assume this identity to access Azure resources.

resource "azurerm_federated_identity_credential" "shared_workload" {
  count               = local.cluster_uses_dedicated_subscription ? 0 : 1
  name                = "aks-shared-workload"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:default:infra-shared"
}

resource "azurerm_federated_identity_credential" "cluster_shared_workload" {
  count               = local.cluster_uses_dedicated_subscription ? 1 : 0
  name                = "aks-cluster-shared-workload"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:default:infra-shared"
}

# Per-app federated credentials — each app on AKS that still uses the
# shared identity gets a fed cred for `system:serviceaccount:<app>:infra-shared`.
# Subset rather than every k8s_app because some apps don't actually federate
# (dead fed creds) and others have migrated to their own per-app identity.
# See `local.shared_identity_apps` in main.tf for the criteria.
resource "azurerm_federated_identity_credential" "shared_workload_app" {
  for_each = {
    for key, value in local.shared_identity_apps : key => value
    if !local.cluster_uses_dedicated_subscription
  }

  name                = "aks-shared-workload-${each.key}"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:${each.key}:infra-shared"
}

resource "azurerm_federated_identity_credential" "cluster_shared_workload_app" {
  for_each = {
    for key, value in local.shared_identity_apps : key => value
    if local.cluster_uses_dedicated_subscription
  }

  name                = "aks-cluster-shared-workload-${each.key}"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:${each.key}:infra-shared"
}

# ExternalDNS — manages DNS records in Azure DNS from Gateway/HTTPRoute resources
resource "azurerm_federated_identity_credential" "external_dns" {
  count               = local.cluster_uses_dedicated_subscription ? 0 : 1
  name                = "aks-external-dns"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:external-dns:external-dns"
}

resource "azurerm_federated_identity_credential" "cluster_external_dns" {
  count               = local.cluster_uses_dedicated_subscription ? 1 : 0
  name                = "aks-cluster-external-dns"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:external-dns:external-dns"
}

# ExternalSecrets — syncs secrets from Key Vault to K8s
resource "azurerm_federated_identity_credential" "external_secrets" {
  count               = local.cluster_uses_dedicated_subscription ? 0 : 1
  name                = "aks-external-secrets"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets"
}

resource "azurerm_federated_identity_credential" "cluster_external_secrets" {
  count               = local.cluster_uses_dedicated_subscription ? 1 : 0
  name                = "aks-cluster-external-secrets"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets"
}

# DNS Zone Contributor — allows ExternalDNS to create/update/delete records
resource "azurerm_role_assignment" "shared_identity_dns" {
  scope                = azurerm_dns_zone.main.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.shared.principal_id
}

# cert-manager — issues certificates via DNS-01 against Azure DNS. Reuses the
# shared identity (already has DNS Zone Contributor); federation ties it to
# the cert-manager controller's ServiceAccount so wildcard certs (e.g.
# *.<app>.dev.romaine.life) can be solved without HTTP-01.
resource "azurerm_federated_identity_credential" "cert_manager" {
  count               = local.cluster_uses_dedicated_subscription ? 0 : 1
  name                = "aks-cert-manager"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_federated_identity_credential" "cluster_cert_manager" {
  count               = local.cluster_uses_dedicated_subscription ? 1 : 0
  name                = "aks-cluster-cert-manager"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}
