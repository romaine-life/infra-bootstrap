# ============================================================================
# Shared Infrastructure - Core Resources
# ============================================================================
# This file contains only shared infrastructure resources that are used
# across multiple applications. App-specific resources should use the
# azure-app module in their respective repositories.
# ============================================================================

# Azure client + resource group data sources. client_config is consumed by
# locals below, output.tf, keyvault.tf, etc. — kept at the top of the file
# so the dependency is obvious at a glance.
data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = "infra"
}

locals {
  # `cluster_subscription_id` is still emitted as a `github_actions_variable`
  # for downstream app workflows (see app/main.tf). The `var.* != ""` shape is
  # preserved because the variable is optional from the workflow's POV.
  cluster_subscription_id         = var.cluster_subscription_id != "" ? var.cluster_subscription_id : data.azurerm_client_config.current.subscription_id
  cluster_resource_group_name     = azurerm_resource_group.cluster.name
  cluster_resource_group_location = azurerm_resource_group.cluster.location
  active_aks_oidc_issuer_url      = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  active_aks_cluster_id           = azurerm_kubernetes_cluster.cluster.id
  active_aks_cluster_name         = azurerm_kubernetes_cluster.cluster.name
}

resource "azurerm_resource_group" "cluster" {
  provider = azurerm.cluster

  name     = var.cluster_resource_group_name
  location = data.azurerm_resource_group.main.location
}

moved {
  from = azurerm_resource_group.cluster[0]
  to   = azurerm_resource_group.cluster
}

# ============================================================================
# Shared Database Infrastructure - Cosmos DB
# ============================================================================
# This file contains shared database resources that can be used by applications.
# Individual applications can create their own databases and containers within
# this Cosmos DB account, or reference this account for data storage.
# ============================================================================

# Cosmos DB account is defined in cosmos-serverless.tf. The previous
# provisioned free-tier account (infra-cosmos) was torn down in this commit
# after apps migrated off it.

# ============================================================================
# Azure App Configuration
# ============================================================================
# Shared App Configuration store for centralised key/value settings consumed
# by all applications.  Other stacks discover the store via
# terraform_remote_state outputs.

resource "azurerm_app_configuration" "main" {
  name                = "infra-appconfig"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "free"
}

resource "azurerm_app_configuration_key" "cosmos_db_endpoint" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "cosmos_db_endpoint"
  value                  = azurerm_cosmosdb_account.serverless.endpoint
}

# ============================================================================
# Shared User-Assigned Managed Identity
# ============================================================================
# Pre-configured identity that apps attach to their Container Apps.
# Common roles are assigned here so app SPs don't need User Access
# Administrator to create role assignments at deploy time.

resource "azurerm_user_assigned_identity" "shared" {
  name                = "infra-shared-identity"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
}

# Key Vault Secrets User — kept for external-secrets, which reads from KV
# to sync secrets into K8s. Apps no longer reuse this identity (each has
# its own narrowed KV grants in their per-app tofu), so the role is now
# narrowly used by exactly one consumer.
resource "azurerm_role_assignment" "shared_identity_keyvault" {
  scope                = data.azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.shared.principal_id
}

# DNS Zone Contributor lives in aks.tf alongside the external-dns +
# cert-manager fed creds. App Configuration Data Reader and Storage Blob
# Data Contributor used to be assigned here for apps' shared use; both
# were removed once every app moved to its own per-app identity (see
# kill-me/tofu/identity.tf etc., plus fzt-frontend-identity.tf and
# llm-explorer-identity.tf in this repo).
# If a future system service needs either, narrow it to its own
# identity rather than re-broadening this one.

# Storage Blob Data Contributor for Nelson's personal identity (local dev API)
resource "azurerm_role_assignment" "nelson_storage" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "cf57d57d-1411-4f59-b517-e9a8600b140a"
}

locals {
  ci_only_apps = toset(["fzt", "fzt-terminal", "fzt-frontend", "fzt-automate", "fzt-browser", "fzt-picker", "fzt-desktop", "mcp-argocd", "mcp-auth", "mcp-azure-personal", "mcp-github", "mcp-glimmung", "mcp-k8s", "mcp-tank-operator", "platform-mcp"])

  # Apps deployed on AKS — gives the app SP AcrPush on romainecr (for CI to
  # push images). Expand as each app migrates off the shared api onto its
  # own K8s Deployment.
  k8s_apps = toset(["ambience", "auth", "house-hunt", "kill-me", "fzt-frontend", "my-homepage", "diagrams", "llm-explorer", "tank-operator", "glimmung", "hermes", "mcp-argocd", "mcp-auth", "mcp-azure-personal", "mcp-github", "mcp-glimmung", "mcp-k8s", "mcp-tank-operator", "void-drifter-infra"])

  # Subset of k8s_apps whose pods federate to infra-shared-identity via
  # `system:serviceaccount:<app>:infra-shared`. Empty: every app has
  # migrated to its own per-app identity (kill-me, house-hunt, diagrams
  # in their own tofu; fzt-frontend and llm-explorer in this repo via
  # fzt-frontend-identity.tf / llm-explorer-identity.tf; glimmung in
  # glimmung/tofu/identity.tf). The convention is fully retired —
  # adding a new app here re-introduces the cross-app blast radius we
  # just dismantled. Don't.
  #
  # The shared_workload_app for_each in aks.tf renders zero resources
  # while this is empty. Once we're confident no rollback is needed, the
  # for_each (and the shared identity itself, azurerm_user_assigned_identity.shared
  # — currently still used by external-secrets for KV reads and by
  # external-dns + cert-manager for DNS Zone Contributor) can be deleted.
  shared_identity_apps = toset([])
  app_default_branch = {
    "fzt" = "main"
  }
  app_topics = {
    "fzt-desktop"        = ["fzt-downstream"]
    "fzt-showcase"       = ["fzt-downstream"]
    "hermes"             = ["hermes-agent", "nous-research", "ai-agent"]
    "mcp-argocd"         = ["mcp-server", "tank-operator"]
    "mcp-auth"           = ["mcp-server", "tank-operator", "auth"]
    "mcp-azure-personal" = ["mcp-server", "tank-operator"]
    "mcp-github"         = ["mcp-server", "tank-operator"]
    "mcp-glimmung"       = ["mcp-server", "glimmung"]
    "mcp-k8s"            = ["mcp-server", "tank-operator"]
    "mcp-tank-operator"  = ["mcp-server", "tank-operator"]
    "platform-mcp"       = ["mcp-server", "tank-operator"]
    "my-homepage"        = ["fzt-downstream"]
    "void-drifter-infra" = ["void-drifter"]
  }
  app_pages_branch = {}
  # Let each app CI principal grant Microsoft Graph app-role assignments,
  # including tenant-wide roles that a downstream app stack may need.
  default_graph_app_role_values = toset([
    "AppRoleAssignment.ReadWrite.All",
  ])
  extra_graph_app_role_values = {
  }

  # Apps whose CI SP runs its own `tofu` pipeline against the shared
  # `nelsontofu` state backend. Membership grants the opt-in set required to
  # plan + apply ordinary app infrastructure: Storage Blob Data Contributor
  # (tfstate), Subscription Contributor (ARM resources), Role Based Access
  # Control Administrator (role assignment writes), plus the
  # TFSTATE_STORAGE_ACCOUNT repo var. Key Vault data-plane access is granted
  # to every infra-bootstrap-created CI principal at subscription scope in
  # the app module.
  #
  # Listed explicitly rather than derived from `!ci_only`: "owns its own
  # tofu" and "is a web app" are independent axes. A backend service
  # like mcp-azure-personal owns its own tofu without being a web app.
  # Add a repo here when its CI grows an `infra/` directory + `tofu`
  # workflow.
  runs_own_tofu_apps = toset([
    "ambience", "auth", "bender-world", "card-utility-stats", "diagrams", "eight-queens",
    "fzt-frontend", "fzt-showcase", "glimmung", "hermes", "house-hunt", "kill-me", "lights",
    "llm-explorer", "mcp-azure-personal", "my-homepage", "tank-operator", "void-drifter-infra",
  ])
}

resource "random_password" "card_utility_stats_vm_admin" {
  length           = 32
  special          = true
  override_special = "!@#$%^&*-_=+?"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "azurerm_key_vault_secret" "card_utility_stats_vm_admin_password" {
  name         = "card-utility-stats-vm-admin-password"
  key_vault_id = data.azurerm_key_vault.main.id
  value        = random_password.card_utility_stats_vm_admin.result
}

import {
  to = module.app["fzt"].github_repository.repo
  id = "fzt"
}

# ambience: pre-existing repo created manually during the initial AKS
# bring-up. Bringing into tofu so CI federated creds + AcrPush get managed
# alongside the other k8s_apps.
import {
  to = module.app["ambience"].github_repository.repo
  id = "ambience"
}

# The following repos were created outside infra-bootstrap (fzt-frontend and
# fzt-automate on 2026-04-07 as stubs, fzt-browser on 2026-04-16 during the
# split, fzt-picker pre-split). Import tells tofu they already exist.

import {
  to = module.app["fzt-frontend"].github_repository.repo
  id = "fzt-frontend"
}

import {
  to = module.app["fzt-automate"].github_repository.repo
  id = "fzt-automate"
}

import {
  to = module.app["fzt-browser"].github_repository.repo
  id = "fzt-browser"
}

import {
  to = module.app["fzt-picker"].github_repository.repo
  id = "fzt-picker"
}

# llm-explorer: pre-existing repo on master branch. Needs the full web
# sub-module (not ci_only) since it's an app with a frontend; currently
# local-only but will be deployed as a SWA later.
import {
  to = module.app["llm-explorer"].github_repository.repo
  id = "llm-explorer"
}

import {
  to = module.app["card-utility-stats"].github_repository.repo
  id = "card-utility-stats"
}

# mcp-tank-operator import lives in imports.tf alongside other recently
# imported pre-existing repos.

moved {
  from = module.app["fuzzy-tiered"]
  to   = module.app["fzt"]
}

moved {
  from = module.app["fuzzy-tiers-showcase"]
  to   = module.app["fzt-showcase"]
}

moved {
  from = module.app["infra-diagram"]
  to   = module.app["diagrams"]
}

# mcp-azure-personal: repo was originally created via the for_each as
# "mcp-azure-admin" on 2026-05-05, then renamed on github.com via
# nelsong6/mcp-azure-personal#1 the same day. The for_each key never
# followed, so FIC subjects and the AAD application display_name
# remained stale (the FIC subject mismatch is why workload identity
# stopped working after the recent chart namespace rename surfaced the
# regression). Rename the for_each key — the github provider treats
# `github_repository.name` changes as in-place via PATCH, so the repo's
# numeric id and the per-app SP's client_id (vars.ARM_CLIENT_ID on the
# downstream repo) are preserved.
moved {
  from = module.app["mcp-azure-admin"]
  to   = module.app["mcp-azure-personal"]
}

module "app" {
  source = "./app"
  # The cluster provider is configured against `var.cluster_subscription_id`
  # so per-app SPs can be granted Owner on the cluster sub from infra-
  # bootstrap (single point of authority). App-specific cluster-scope
  # resources go in each app's own tofu.
  providers = {
    azurerm         = azurerm
    azurerm.cluster = azurerm.cluster
  }
  for_each = toset([
    "ambience",
    "auth",
    "bender-world",
    "card-utility-stats",
    "diagrams",
    "eight-queens",
    "fzt",
    "fzt-automate",
    "fzt-browser",
    "fzt-desktop",
    "fzt-frontend",
    "fzt-picker",
    "fzt-showcase",
    "fzt-terminal",
    "glimmung",
    "hermes",
    "house-hunt",
    "kill-me",
    "lights",
    "llm-explorer",
    "mcp-argocd",
    "mcp-auth",
    "mcp-azure-personal",
    "mcp-github",
    "mcp-glimmung",
    "mcp-k8s",
    "mcp-tank-operator",
    "my-homepage",
    "platform-mcp",
    "tank-operator",
    "void-drifter-infra",
  ])

  name                           = each.key
  ci_only                        = contains(local.ci_only_apps, each.key)
  tfstate_access                 = contains(local.runs_own_tofu_apps, each.key)
  manages_subscription_resources = contains(local.runs_own_tofu_apps, each.key)
  manages_role_assignments       = contains(local.runs_own_tofu_apps, each.key)
  default_branch                 = lookup(local.app_default_branch, each.key, "main")
  topics                         = lookup(local.app_topics, each.key, [])
  pages_branch                   = lookup(local.app_pages_branch, each.key, "")
  key_vault_name                 = data.azurerm_key_vault.main.name
  key_vault_id                   = data.azurerm_key_vault.main.id
  app_config_id                  = azurerm_app_configuration.main.id
  cosmos_account_id              = azurerm_cosmosdb_account.serverless.id
  cosmos_account_name            = azurerm_cosmosdb_account.serverless.name
  cosmos_resource_group_name     = data.azurerm_resource_group.main.name
  arm_tenant_id                  = data.azurerm_client_config.current.tenant_id
  arm_subscription_id            = data.azurerm_client_config.current.subscription_id
  cluster_subscription_id        = local.cluster_subscription_id
  google_client_id               = data.azurerm_key_vault_secret.google_oauth_client_id.value
  extra_graph_app_role_values    = setunion(local.default_graph_app_role_values, lookup(local.extra_graph_app_role_values, each.key, toset([])))
}
