# ============================================================================
# Shared OAuth App Registrations
# ============================================================================
# OAuth credentials shared across all projects (my-homepage, kill-me, etc.).
# Microsoft: Azure AD App Registration managed here.
# Google:    Created via bootstrap/setup-google-oauth.ps1, secrets in Key Vault.
# GitHub:    GitHub App created via bootstrap/setup-github-app.ps1.

# ============================================================================
# Microsoft "Sign in with Microsoft" (shared across all projects)
# ============================================================================

data "azuread_client_config" "current" {}

resource "azuread_application" "microsoft_login" {
  display_name     = "romaine.life - Social Login"
  sign_in_audience = "AzureADandPersonalMicrosoftAccount"

  # The azuread provider doesn't auto-add the creating SP as owner — without
  # this, `Application.ReadWrite.OwnedBy` (this repo's Graph permission)
  # returns 403 on any subsequent update. Declared explicitly so the owners
  # list matches the tofu-run principal.
  owners = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  single_page_application {
    redirect_uris = [
      # Custom domains
      "https://homepage.romaine.life/",
      "https://workout.romaine.life/",
      "https://plants.romaine.life/",
      # SWA bypass URLs (auto-generated, stable)
      "https://white-sea-0beb0bf1e.7.azurestaticapps.net/",    # homepage
      "https://nice-sea-09c30861e.2.azurestaticapps.net/",     # workout
      "https://lemon-island-070f8051e.2.azurestaticapps.net/", # plant-agent
      # Local dev
      "http://localhost:5173/",
      "http://localhost:5500/",
    ]
  }

  # auth.romaine.life onboarding: the new central auth service does
  # authorization-code-with-client-secret (a web flow, not SPA), so its
  # callback URL goes here. SPA URIs above stay for now and get pruned
  # in a follow-up after every per-app frontend has switched to the
  # redirect-to-auth.romaine.life flow.
  web {
    redirect_uris = [
      "https://auth.romaine.life/api/auth/callback/microsoft",
      "http://localhost:3000/api/auth/callback/microsoft",
    ]
  }
}

resource "azuread_application_password" "microsoft_login" {
  application_id = azuread_application.microsoft_login.id
  display_name   = "passport-microsoft"
}

# Store Microsoft OAuth credentials in shared Key Vault so backends can
# read them at runtime via managed identity.

resource "azurerm_key_vault_secret" "microsoft_oauth_client_id" {
  name         = "microsoft-oauth-client-id"
  value        = azuread_application.microsoft_login.client_id
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "microsoft_oauth_client_secret" {
  name         = "microsoft-oauth-client-secret"
  value        = azuread_application_password.microsoft_login.value
  key_vault_id = data.azurerm_key_vault.main.id
}

# ============================================================================
# ArgoCD OIDC (server-side auth code flow)
# ============================================================================
# Dedicated app registration for ArgoCD SSO. Uses the authorization code
# flow with a client secret — separate from the SPA social login app above.

resource "azuread_application" "argocd" {
  display_name     = "ArgoCD"
  sign_in_audience = "AzureADandPersonalMicrosoftAccount"

  # See comment on microsoft_login above — same ownership self-assertion.
  owners = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = [
      "https://argocd.romaine.life/api/dex/callback",
    ]
  }

  optional_claims {
    id_token {
      name = "email"
    }
  }
}

resource "azuread_application_password" "argocd" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-oidc"
}

resource "azurerm_key_vault_secret" "argocd_oidc_client_id" {
  name         = "argocd-oidc-client-id"
  value        = azuread_application.argocd.client_id
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "argocd_oidc_client_secret" {
  name         = "argocd-oidc-client-secret"
  value        = azuread_application_password.argocd.value
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "oauth2_proxy_cookie_secret" {
  name         = "oauth2-proxy-cookie-secret"
  value        = random_password.oauth2_proxy_cookie.result
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "random_password" "oauth2_proxy_cookie" {
  length  = 32
  special = false
}

# ============================================================================
# Google "Sign in with Google" (shared across all projects)
# ============================================================================
# Google OAuth credentials are created manually via the GCP Console and stored
# in Key Vault by bootstrap/setup-google-oauth.ps1. We read them as data
# sources so Terraform can reference them in App Configuration.

data "azurerm_key_vault_secret" "google_oauth_client_id" {
  name         = "google-oauth-client-id"
  key_vault_id = data.azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "google_oauth_client_secret" {
  name         = "google-oauth-client-secret"
  key_vault_id = data.azurerm_key_vault.main.id
}

# ============================================================================
# App Configuration Key Vault References (shared across all projects)
# ============================================================================
# These let apps read OAuth credentials from App Configuration, which resolves
# the actual values from Key Vault transparently.

resource "azurerm_app_configuration_key" "google_oauth_client_id" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "google_oauth_client_id"
  type                   = "vault"
  vault_key_reference    = data.azurerm_key_vault_secret.google_oauth_client_id.versionless_id
}

resource "azurerm_app_configuration_key" "google_oauth_client_secret" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "google_oauth_client_secret"
  type                   = "vault"
  vault_key_reference    = data.azurerm_key_vault_secret.google_oauth_client_secret.versionless_id
}

resource "azurerm_app_configuration_key" "google_oauth_client_id_plain" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "google_oauth_client_id_plain"
  value                  = data.azurerm_key_vault_secret.google_oauth_client_id.value
}

resource "azurerm_app_configuration_key" "microsoft_oauth_client_id_plain" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "microsoft_oauth_client_id_plain"
  value                  = azuread_application.microsoft_login.client_id
}

resource "azurerm_app_configuration_key" "microsoft_oauth_client_id" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "microsoft_oauth_client_id"
  type                   = "vault"
  vault_key_reference    = azurerm_key_vault_secret.microsoft_oauth_client_id.versionless_id
}

resource "azurerm_app_configuration_key" "microsoft_oauth_client_secret" {
  configuration_store_id = azurerm_app_configuration.main.id
  key                    = "microsoft_oauth_client_secret"
  type                   = "vault"
  vault_key_reference    = azurerm_key_vault_secret.microsoft_oauth_client_secret.versionless_id
}
