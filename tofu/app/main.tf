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

# ── Optional capability opt-ins ──────────────────────────────────────
# Independent of ci_only. Each flag turns on the specific Azure / GitHub
# Actions plumbing required for a downstream capability. Defaults are
# false; the root module enables them per-app via locals.

variable "tfstate_access" {
  description = "When true, grant Storage Blob Data Contributor at subscription scope and set the TFSTATE_STORAGE_ACCOUNT repo variable so this app's CI SP can read/write the shared `nelsontofu` state backend. Required for any repo that runs its own `tofu` pipeline."
  type        = bool
  default     = false
}

variable "manages_subscription_resources" {
  description = "When true, grant Contributor at subscription scope so this app's CI SP can create/update/destroy ordinary ARM resources (managed identities, federated credentials, key vault secrets at control-plane, Cosmos data-plane role assignments, Postgres Flexible Server admins, etc.). Excludes role assignment write — that's gated separately on `manages_role_assignments`. Required for any repo whose `tofu` plan creates Azure resources."
  type        = bool
  default     = false
}

variable "manages_role_assignments" {
  description = "When true, grant Role Based Access Control Administrator at subscription scope so this app's CI SP can create/destroy `azurerm_role_assignment` resources. Contributor explicitly excludes role assignment write, so apps whose `tofu` declares role assignments need this in addition to `manages_subscription_resources`."
  type        = bool
  default     = false
}

variable "manages_keyvault_secrets" {
  description = "When true, grant Key Vault Secrets Officer (read+write data-plane) on `var.key_vault_id`. When false (default), the `ci_only` path grants Key Vault Secrets User (read-only) instead. Required for any repo whose `tofu` writes KV secrets."
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

# `azuread_client_config` resolves to whichever identity is currently
# running this apply — i.e. infra-bootstrap's own tofu CI SP. Used below
# to register that SP as owner of every per-app Application + Service
# Principal we create, so the same SP that creates them can also destroy
# them on a future apply via `Application.ReadWrite.OwnedBy`.
data "azuread_client_config" "current" {}

# Per-app Azure AD application + service principal
resource "azuread_application" "app" {
  display_name = var.name
  # Microsoft Graph implicitly adds the creator as an Application owner on
  # POST /applications, but setting it explicitly here makes the behavior
  # contractual rather than implicit and keeps Application and Service
  # Principal owners symmetrical.
  owners = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "app" {
  client_id = azuread_application.app.client_id
  # Unlike Application, the Graph SP creation endpoint does NOT
  # implicitly assign an owner — `azuread_service_principal` docs:
  # "By default, no owners are assigned." Without this line, every SP
  # the for_each created has empty owners, so the corresponding
  # `Application.ReadWrite.OwnedBy` permission on `infra_ci` doesn't
  # allow deleting them on a later destroy (Graph 403). That's what
  # left the `tank-operator-oauth` / `tank-operator-oauth-test` SPs
  # un-destroyable in tank-operator's tofu state after #471. Setting
  # this on every new SP closes the gap; existing SPs in the for_each
  # gain an owner in-place on the next apply.
  owners = [data.azuread_client_config.current.object_id]
}

# Key Vault Secrets User (read-only) — the default for any app that hasn't
# opted in to managing secrets. Mutually exclusive with the Officer grant
# below; opting `manages_keyvault_secrets = true` swaps User for Officer.
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  count                = var.manages_keyvault_secrets ? 0 : 1
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.app.object_id
}

# Key Vault Secrets Officer (read+write data-plane). Opt-in via
# var.manages_keyvault_secrets.
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  count                = var.manages_keyvault_secrets ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azuread_service_principal.app.object_id
}

# Subscription Contributor — broad ARM resource management. Opt-in via
# var.manages_subscription_resources. Does NOT grant role assignment
# write (that's gated on var.manages_role_assignments via the resource
# below); Contributor explicitly excludes Microsoft.Authorization/*.
resource "azurerm_role_assignment" "subscription_contributor" {
  count                = var.manages_subscription_resources ? 1 : 0
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.app.object_id
}

# Role Based Access Control Administrator — needed to create/destroy
# `azurerm_role_assignment` resources. Opt-in via
# var.manages_role_assignments.
resource "azurerm_role_assignment" "rbac_admin" {
  count                = var.manages_role_assignments ? 1 : 0
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
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

# ── Tofu state backend access (opt-in via var.tfstate_access) ──────
# Lives in the parent module so a ci_only app like mcp-azure-personal
# can opt in without becoming a web app. Previously these two resources
# lived in the web sub-module, gated implicitly on `ci_only = false`;
# `tofu/app/moved.tf` carries the state addresses forward.

resource "azurerm_role_assignment" "storage_blob_contributor" {
  count                = var.tfstate_access ? 1 : 0
  scope                = "/subscriptions/${var.arm_subscription_id}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.app.object_id
}

resource "github_actions_variable" "tfstate_storage_account" {
  count         = var.tfstate_access ? 1 : 0
  repository    = github_repository.repo.name
  variable_name = "TFSTATE_STORAGE_ACCOUNT"
  value         = "nelsontofu"
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
