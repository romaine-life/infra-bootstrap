# OIDC trust for this repo after its transfer to romaine-life/infra-bootstrap.
# The historical nelsong6 trust was created during bootstrap and remains until
# every transfer-dependent path has been updated.

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
