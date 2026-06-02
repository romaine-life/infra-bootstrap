# ============================================================================
# Landing Page CI/CD
# ============================================================================
# The landing page itself runs in AKS (namespace `landing-page`, ArgoCD app
# at k8s/apps/landing-page.yaml, source manifests in romaine-life/landing-page).
# This file owns the GitHub repo and the federated identity that lets that
# repo's GitHub Actions push images to ACR via OIDC. The previous Static Web
# App + apex A record + custom domain were retired when the splash moved to
# AKS — apex DNS for romaine.life is now created by external-dns from the
# landing-page HTTPRoute hostname.
# ============================================================================

resource "github_repository" "landing_page" {
  provider = github.romaine_life

  name       = "landing-page"
  visibility = "public"
  auto_init  = true

  has_issues = true

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  delete_branch_on_merge = true
}

data "azuread_application" "main" {
  client_id = data.azurerm_client_config.current.client_id
}

resource "azuread_application_federated_identity_credential" "landing_page_github_actions_main" {
  application_id = data.azuread_application.main.id
  display_name   = "landing-page-github-actions-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${github_repository.landing_page.full_name}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "landing_page_github_actions_prod" {
  application_id = data.azuread_application.main.id
  display_name   = "landing-page-github-actions-prod"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${github_repository.landing_page.full_name}:environment:prod"
}

resource "github_actions_variable" "landing_page_arm_client_id" {
  provider = github.romaine_life

  repository    = github_repository.landing_page.name
  variable_name = "ARM_CLIENT_ID"
  value         = data.azurerm_client_config.current.client_id
}

resource "github_actions_variable" "landing_page_arm_tenant_id" {
  provider = github.romaine_life

  repository    = github_repository.landing_page.name
  variable_name = "ARM_TENANT_ID"
  value         = data.azurerm_client_config.current.tenant_id
}

resource "github_actions_variable" "landing_page_arm_subscription_id" {
  provider = github.romaine_life

  repository    = github_repository.landing_page.name
  variable_name = "ARM_SUBSCRIPTION_ID"
  value         = data.azurerm_client_config.current.subscription_id
}
