# ============================================================================
# Romaine.life Shared Auth Policy
# ============================================================================
# Canonical human admin allowlist for romaine.life control-plane apps.
# App charts consume this via External Secrets and map it into their local
# auth environment as needed.

locals {
  romaine_life_admin_emails = [
    "nelson@romaine.life",
    "nelson-devops-project@outlook.com",
    "brenden.owens39@gmail.com",
    "gantonski@gmail.com",
    "menacewwo@gmail.com",
  ]
}

resource "azurerm_key_vault_secret" "romaine_life_admin_emails" {
  name         = "romaine-life-admin-emails"
  key_vault_id = data.azurerm_key_vault.main.id
  value        = join(",", local.romaine_life_admin_emails)
  content_type = "text/csv"
}
