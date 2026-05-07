terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# ── Core variables (all apps) ───────────────────────────────────────

variable "name" {
  type = string
}

variable "key_vault_name" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "arm_tenant_id" {
  type = string
}

variable "arm_subscription_id" {
  type = string
}

variable "default_branch" {
  type    = string
  default = "main"
}

variable "ci_only" {
  description = "When true, only create OIDC identity + KV read access (no web app roles)."
  type        = bool
  default     = false
}

variable "topics" {
  description = "GitHub repository topics for categorization and discovery."
  type        = list(string)
  default     = []
}

variable "pages_branch" {
  description = "Branch to serve GitHub Pages from. Empty string disables Pages."
  type        = string
  default     = ""
}

# ── Web-only variables (ignored when ci_only = true) ────────────────

variable "app_config_id" {
  type    = string
  default = ""
}

variable "cosmos_account_id" {
  type    = string
  default = ""
}

variable "cosmos_account_name" {
  type    = string
  default = ""
}

variable "cosmos_resource_group_name" {
  type    = string
  default = ""
}

variable "google_client_id" {
  type    = string
  default = ""
}

variable "extra_graph_app_role_values" {
  description = "Additional Microsoft Graph application role values to grant to the app CI service principal."
  type        = set(string)
  default     = []
}

# ── Core resources (all apps) ──────────────────────────────────────

resource "github_repository" "repo" {
  name       = var.name
  visibility = "public"
  auto_init  = true
  topics     = var.topics

  # terraform-github-provider defaults has_issues to false, unlike GitHub's
  # web UI which defaults it to true. Explicitly enable so new apps land
  # with issues on.
  has_issues = true

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  delete_branch_on_merge = true

  dynamic "pages" {
    for_each = var.pages_branch != "" ? [1] : []
    content {
      source {
        branch = var.pages_branch
        path   = "/"
      }
    }
  }
}

# Per-app Azure AD application + service principal
resource "azuread_application" "app" {
  display_name = var.name
}

resource "azuread_service_principal" "app" {
  client_id = azuread_application.app.client_id
}

# Key Vault Secrets User (read-only) — ci_only apps get this instead of Officer
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  count                = var.ci_only ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.app.object_id
}

# OIDC federated credentials — default branch + pull requests
resource "azuread_application_federated_identity_credential" "github_actions_main" {
  application_id = azuread_application.app.id
  display_name   = "${var.name}-github-actions-${var.default_branch}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${github_repository.repo.full_name}:ref:refs/heads/${var.default_branch}"
}

resource "azuread_application_federated_identity_credential" "github_actions_pr" {
  application_id = azuread_application.app.id
  display_name   = "${var.name}-github-actions-pr"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${github_repository.repo.full_name}:pull_request"
}

resource "github_actions_variable" "key_vault_name" {
  repository    = github_repository.repo.name
  variable_name = "KEY_VAULT_NAME"
  value         = var.key_vault_name
}

resource "github_actions_variable" "arm_client_id" {
  repository    = github_repository.repo.name
  variable_name = "ARM_CLIENT_ID"
  value         = azuread_application.app.client_id
}

resource "github_actions_variable" "arm_tenant_id" {
  repository    = github_repository.repo.name
  variable_name = "ARM_TENANT_ID"
  value         = var.arm_tenant_id
}

resource "github_actions_variable" "arm_subscription_id" {
  repository    = github_repository.repo.name
  variable_name = "ARM_SUBSCRIPTION_ID"
  value         = var.arm_subscription_id
}

# ── Web app resources (skipped when ci_only = true) ────────────────

module "web" {
  source = "./web"
  count  = var.ci_only ? 0 : 1

  # Pass the repo's resource attribute (not the input string) so tofu sees
  # this submodule's `github_actions_variable` resources as dependent on
  # the repo's creation. Without this, on a brand-new app's first apply,
  # the variable POSTs race the repo create and 404.
  repo_name                   = github_repository.repo.name
  principal_id                = azuread_service_principal.app.object_id
  application_id              = azuread_application.app.id
  arm_subscription_id         = var.arm_subscription_id
  key_vault_id                = var.key_vault_id
  app_config_id               = var.app_config_id
  cosmos_account_id           = var.cosmos_account_id
  cosmos_account_name         = var.cosmos_account_name
  cosmos_resource_group_name  = var.cosmos_resource_group_name
  google_client_id            = var.google_client_id
  extra_graph_app_role_values = var.extra_graph_app_role_values
}
