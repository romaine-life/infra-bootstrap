# Future OIDC trust for transferring this repo from nelsong6/infra-bootstrap
# to romaine-life/infra-bootstrap. The existing nelsong6 trust was created
# during bootstrap; these extra subjects let the workflow keep Azure access
# immediately after the GitHub repository transfer.

resource "azuread_application_federated_identity_credential" "infra_bootstrap_romaine_life_main" {
  application_id = data.azuread_application.infra_ci.id
  display_name   = "infra-bootstrap-romaine-life-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:romaine-life/infra-bootstrap:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "infra_bootstrap_romaine_life_pr" {
  application_id = data.azuread_application.infra_ci.id
  display_name   = "infra-bootstrap-romaine-life-pr"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:romaine-life/infra-bootstrap:pull_request"
}
