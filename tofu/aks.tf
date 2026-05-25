# ============================================================================
# Azure Kubernetes Service (AKS)
# ============================================================================
# Shared AKS cluster replacing Azure Container Apps. Each app gets its own
# Deployment instead of sharing a single always-on API. Ingress replaces SWA.
# ExternalSecrets replaces direct Key Vault references.
#
# Workload identity is enabled so pods can assume managed identities via
# federated credentials (see shared_workload below).
#
# The cluster lives in `var.cluster_subscription_id` via the `azurerm.cluster`
# provider alias. This file used to carry a paired `.main` / `.cluster` shape
# (count-gated by `cluster_uses_dedicated_subscription`) so the cluster could
# theoretically be co-located with the rest of tofu state in a single
# subscription. The `.main` halves were dead code — they never made it into
# state — so they were removed along with the local. `moved {}` blocks below
# migrate the surviving `.cluster[0]` addresses to bare `.cluster`.
# ============================================================================

resource "azurerm_kubernetes_cluster" "cluster" {
  provider = azurerm.cluster

  name                = "infra-aks"
  resource_group_name = local.cluster_resource_group_name
  location            = local.cluster_resource_group_location
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
    vm_size         = "Standard_E2bs_v5"
    os_disk_size_gb = 128
    vnet_subnet_id  = azurerm_subnet.cluster_aks_nodes.id

    # Autoscale 3-4 nodes. min_count was 2 until 2026-05-25 — bumped to 3
    # so the NATS chart's required-hostname podAntiAffinity (R=3 stream,
    # one replica per node, see k8s/nats/values.yaml) can always be
    # satisfied. With min_count=2, an off-hours scale-down would strand
    # one NATS replica Pending and immediately produce the same
    # JetStream quorum-loss shape the 2026-05-25 incident showed.
    # max_count bumped from 3 to 4 on 2026-05-25 to absorb the
    # glimmung Postgres-migration rolling-deploy CPU pressure: the
    # 2h foundation pod (nelsong6/glimmung#575) couldn't schedule
    # because all 3 nodes were at CPU limit and the autoscaler was
    # already at max group size. 4 nodes gives the scheduler
    # headroom for the rollout surge plus the existing workload.
    auto_scaling_enabled = true
    min_count            = 3
    max_count            = 4

    # AKS auto-populates upgrade_settings on the node pool; declare these
    # explicitly so tofu doesn't see drift and try to unset
    # undrainable_node_behavior (which forces full cluster replacement).
    #
    # max_surge="33%" matches Microsoft's documented recommendation for
    # production system pools
    # (https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster#customize-node-surge-upgrade).
    # At 2-3 nodes 33% rounds up to 1 surge node, same as the previous 10%
    # — no behavior change at this size. The win shows up if/when the pool
    # scales: 6 nodes → 2 surge instead of 1, 10 nodes → 4 surge instead of
    # 1. Upgrade wall-clock drops roughly linearly. The doubling-cost
    # concern of higher values like "100%" is avoided because surge nodes
    # only exist for the duration of one node's drain (single-digit minutes).
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "33%"
      node_soak_duration_in_minutes = 0
      undrainable_node_behavior     = "Schedule"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }
}

moved {
  from = azurerm_kubernetes_cluster.cluster[0]
  to   = azurerm_kubernetes_cluster.cluster
}

# ============================================================================
# Workload Identity — Federated Credential for Shared Identity
# ============================================================================
# Bridges the existing infra-shared-identity (which already has Cosmos DB,
# App Config, Key Vault, and Storage roles) to the AKS OIDC issuer.
# Pods using the "infra-shared" service account in the "default" namespace
# can assume this identity to access Azure resources.

resource "azurerm_federated_identity_credential" "cluster_shared_workload" {
  name                = "aks-cluster-shared-workload"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:default:infra-shared"
}

moved {
  from = azurerm_federated_identity_credential.cluster_shared_workload[0]
  to   = azurerm_federated_identity_credential.cluster_shared_workload
}

# Per-app federated credentials — each app on AKS that still uses the
# shared identity gets a fed cred for `system:serviceaccount:<app>:infra-shared`.
# Subset rather than every k8s_app because some apps don't actually federate
# (dead fed creds) and others have migrated to their own per-app identity.
# See `local.shared_identity_apps` in main.tf for the criteria.
resource "azurerm_federated_identity_credential" "cluster_shared_workload_app" {
  for_each = local.shared_identity_apps

  name                = "aks-cluster-shared-workload-${each.key}"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:${each.key}:infra-shared"
}

# ExternalDNS — manages DNS records in Azure DNS from Gateway/HTTPRoute resources
resource "azurerm_federated_identity_credential" "cluster_external_dns" {
  name                = "aks-cluster-external-dns"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:external-dns:external-dns"
}

moved {
  from = azurerm_federated_identity_credential.cluster_external_dns[0]
  to   = azurerm_federated_identity_credential.cluster_external_dns
}

# ExternalSecrets — syncs secrets from Key Vault to K8s
resource "azurerm_federated_identity_credential" "cluster_external_secrets" {
  name                = "aks-cluster-external-secrets"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets"
}

moved {
  from = azurerm_federated_identity_credential.cluster_external_secrets[0]
  to   = azurerm_federated_identity_credential.cluster_external_secrets
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
resource "azurerm_federated_identity_credential" "cluster_cert_manager" {
  name                = "aks-cluster-cert-manager"
  resource_group_name = data.azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.shared.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

moved {
  from = azurerm_federated_identity_credential.cluster_cert_manager[0]
  to   = azurerm_federated_identity_credential.cluster_cert_manager
}
