# FORGEJO-3: additive trust for the active repositories whose current CI logs
# into Azure, including calls through pipeline-templates. Keep GitHub trust
# until each repository has completed its own migration.
#
# Verified against a real Forgejo 15 job token in infra-bootstrap run 1:
# https://forgejo.romaine.life/romaine-life/infra-bootstrap/actions/runs/1
# iss=https://forgejo.romaine.life/api/actions
# aud=api://AzureADTokenExchange
# sub=repo:romaine-life/infra-bootstrap:ref:refs/heads/FORGEJO-3-batch-azure-oidc
# Pull requests use repo:OWNER/REPO:pull_request (Forgejo 15 OIDC reference).
# https://forgejo.org/docs/v15.0/user/actions/security-openid-connect/
locals {
  forgejo_ci_apps = toset([
    "ambience",
    "auth",
    "chess-tactics",
    "crenellation",
    "eight-queens",
    "fzt-browser",
    "kill-me",
    "lights",
    "my-homepage",
    "spirelens",
    "tank-operator",
  ])

  # Reference the existing registrations, rather than provisioning new apps or
  # service principals. These are the same apps exported as ARM_CLIENT_ID.
  forgejo_ci_applications = merge(
    { for name in local.forgejo_ci_apps : "romaine-life/${name}" => module.app_org[name].application_id },
    {
      "romaine-life/infra-bootstrap" = data.azuread_application.infra_ci.id
      "romaine-life/landing-page"    = data.azuread_application.main.id
    },
  )
}

resource "azuread_application_federated_identity_credential" "forgejo_ci_main" {
  for_each = local.forgejo_ci_applications

  application_id = each.value
  display_name   = "${split("/", each.key)[1]}-forgejo-actions-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://forgejo.romaine.life/api/actions"
  subject        = "repo:${each.key}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "forgejo_ci_pr" {
  for_each = local.forgejo_ci_applications

  application_id = each.value
  display_name   = "${split("/", each.key)[1]}-forgejo-actions-pr"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://forgejo.romaine.life/api/actions"
  subject        = "repo:${each.key}:pull_request"
}
