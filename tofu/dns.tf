# ============================================================================
# DNS Zone
# ============================================================================
# The DNS zone is the shared domain infrastructure (romaine.life) used by
# all applications. Each app creates its own subdomains under this zone.

resource "azurerm_dns_zone" "main" {
  name                = "romaine.life"
  resource_group_name = data.azurerm_resource_group.main.name

}

# ============================================================================
# Shared DNS Configuration
# ============================================================================
# This file contains DNS records that are shared across the domain, such as
# email (MX, SPF), autodiscover, and apex domain records. Subdomain records
# are managed by each app's repository.
# ============================================================================

# ============================================================================
# Email DNS Records (Google Workspace)
# ============================================================================

# MX Records - Email delivery via Google Workspace
resource "azurerm_dns_mx_record" "email" {
  name                = "@" # Root domain
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    preference = 1
    exchange   = "aspmx.l.google.com"
  }

  record {
    preference = 5
    exchange   = "alt1.aspmx.l.google.com"
  }

  record {
    preference = 5
    exchange   = "alt2.aspmx.l.google.com"
  }

  record {
    preference = 10
    exchange   = "alt3.aspmx.l.google.com"
  }

  record {
    preference = 10
    exchange   = "alt4.aspmx.l.google.com"
  }

}

# Root domain TXT records (SPF, Google site verification)
resource "azurerm_dns_txt_record" "apex" {
  name                = "@" # Root domain
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    value = "v=spf1 include:_spf.google.com ~all"
  }

  record {
    value = "google-site-verification=bIQ8zuUK_DUCCoYi8zUF1CxK_Hn-1Ipah9vgn4PN2z4"
  }

  # Second Search Console property — added 2026-05-16 so we can request a
  # review of the Safe Browsing phishing flag that Chrome's classifier put
  # on auth.romaine.life right after first deploy. A Domain property on
  # romaine.life covers all subdomains, including the flagged one.
  record {
    value = "google-site-verification=wyso_nLFF8k8_sFT6reUtq456NpYBaRcWFxv52ERfhU"
  }

}

# DMARC Record - Email authentication policy
resource "azurerm_dns_txt_record" "dmarc" {
  name                = "_dmarc"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    value = "v=DMARC1; p=quarantine; rua=mailto:nelson@romaine.life"
  }

}

# DKIM Record - Google Workspace email authentication
# Generate the DKIM key in Google Admin Console:
# Apps > Google Workspace > Gmail > Authenticate email > Generate new record
# Then replace the placeholder value below with the generated key.
resource "azurerm_dns_txt_record" "dkim" {
  name                = "google._domainkey" # Google Workspace selector
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 3600

  record {
    value = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5IrwONgV1pb5Y5PIsWZOrkwEdrG3I6us0tg/bnXtc69LaBU+MPwzG3Tx+SIsnuOza3pfc/c6rKcn8hVp+jWat0ZAZsrpQg2eh8V9DokPGf7Cre+8QQkmA9LapcW33SsKsx5BSAtlU+6vrmJrYHafNFTNFjgplOTjge7gRiVzHir2i7Wf08f4O4XVMjmu4bD9XwCSQm+eJ1qszLrjDWHd7OxlqD1wkEuBtIivVkZLjczlvEGl0itmyvX232+oSr+BLmJBrDG4wQ5pmMK7s2jXW8zGFW5s1TqsHTwrYXCsHrdY4me9Z7po1aIz8T2NbLerQ1hv0BMB75z+utpcRlMwPQIDAQAB"
  }

}


