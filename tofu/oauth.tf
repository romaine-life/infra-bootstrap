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

  # auth.romaine.life is the only consumer of this app reg. It does the
  # Microsoft authorization-code-with-client-secret flow (web, not SPA) and
  # exchanges sessions for downstream apps via /api/auth/token. Per-app
  # browser MSAL flows (homepage, workout/kill-me, plants/plant-agent,
  # investing, househunt, glimmung) all retired alongside their own Entra
  # app regs; the previously-listed SPA redirect URIs no longer have any
  # caller and were pruned here.
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

# ArgoCD's dedicated "ArgoCD" Microsoft app registration + its OIDC client
# secrets (argocd-oidc-client-id/secret, formerly here and in
# platform-keyvaults.tf) were retired 2026-05-30. ArgoCD human SSO now
# federates through auth.romaine.life's OIDC provider via Dex (see
# k8s/argocd/values.yaml + argocd-dex-romaine-externalsecret.yaml), so the
# direct Microsoft connector and its credentials have no remaining consumer.
# Deleting the resource blocks destroys the app registration, its password,
# and both KV-secret copies on the next apply.

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
