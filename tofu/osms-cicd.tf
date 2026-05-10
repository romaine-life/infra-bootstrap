# OSMS is a standalone observability repo, but it uses the same GitHub Actions
# Azure app registration as infra-bootstrap. Add explicit OIDC subjects so the
# repo can run its own OpenTofu plan/apply workflow.

data "azuread_application" "infra_ci" {
  client_id = "043b35c3-f5de-4578-acd2-8b8f4c78f461"
}

resource "azuread_application_federated_identity_credential" "osms_github_actions_main" {
  application_id = data.azuread_application.infra_ci.id
  display_name   = "osms-github-actions-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:nelsong6/osms:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "osms_github_actions_pr" {
  application_id = data.azuread_application.infra_ci.id
  display_name   = "osms-github-actions-pr"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:nelsong6/osms:pull_request"
}
