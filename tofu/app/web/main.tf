# ============================================================================
# Web app resources — heavy roles and variables that CLI tools don't need.
# Called from the parent app module when ci_only = false.
# ============================================================================

terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "repo_name" {
  type = string
}

variable "principal_id" {
  type = string
}

variable "application_id" {
  type = string
}

variable "arm_subscription_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "app_config_id" {
  type = string
}

variable "cosmos_account_id" {
  type = string
}

variable "cosmos_account_name" {
  type = string
}

variable "cosmos_resource_group_name" {
  type = string
}

variable "google_client_id" {
  type = string
}

variable "extra_graph_app_role_values" {
  type    = set(string)
  default = []
}

# Contributor (subscription scope)
resource "azurerm_role_assignment" "contributor" {
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = var.principal_id
}

# RBAC Admin (subscription scope)
resource "azurerm_role_assignment" "rbac_admin" {
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = var.principal_id
}

# Key Vault Secrets Officer (read + write)
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.principal_id
}

# App Configuration Data Owner
resource "azurerm_role_assignment" "appconfig_data_owner" {
  scope                = var.app_config_id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = var.principal_id
}

# Storage Blob Data Contributor (subscription scope)
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.principal_id
}

# Cosmos DB Built-in Data Reader
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_data_reader" {
  resource_group_name = var.cosmos_resource_group_name
  account_name        = var.cosmos_account_name
  role_definition_id  = "${var.cosmos_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = var.principal_id
  scope               = var.cosmos_account_id
}

# Grant SP permission to manage its own Azure AD app registration (e.g. redirect URIs).
# Application.ReadWrite.OwnedBy app role from Microsoft Graph.
data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_app_role_assignment" "app_readwrite_owned" {
  app_role_id         = "18a4783c-866b-4cc7-a460-3d5e5662c884"
  principal_object_id = var.principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

resource "azuread_app_role_assignment" "extra_graph_app_roles" {
  for_each = var.extra_graph_app_role_values

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = var.principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# OIDC federated credential for prod environment
resource "azuread_application_federated_identity_credential" "github_actions_prod" {
  application_id = var.application_id
  display_name   = "${var.repo_name}-github-actions-prod"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:nelsong6/${var.repo_name}:environment:prod"
}

# GitHub Actions variables
resource "github_actions_variable" "tfstate_storage_account" {
  repository    = var.repo_name
  variable_name = "TFSTATE_STORAGE_ACCOUNT"
  value         = "nelsontofu"
}

resource "github_actions_variable" "google_client_id" {
  repository    = var.repo_name
  variable_name = "GOOGLE_CLIENT_ID"
  value         = var.google_client_id
}
