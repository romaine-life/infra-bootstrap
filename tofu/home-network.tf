# ============================================================================
# Home network TLS (*.home.romaine.life)
# ============================================================================
# Names under home.romaine.life are answered only by the home router's
# dnsmasq (ASUS LAN domain = home.romaine.life) and are deliberately absent
# from public DNS. The only public footprint is what Let's Encrypt needs to
# issue a wildcard cert for them via DNS-01:
#
#   _acme-challenge.home.romaine.life  CNAME  wildcard.home-acme.romaine.life
#
# The ACME client (lego on the Synology NAS) writes the challenge TXT into
# the tiny delegated zone home-acme.romaine.life. Its identity is scoped to
# that zone alone, so a leaked NAS credential cannot touch anything in
# romaine.life. lego deletes the TXT record set on cleanup, which is why the
# scope is a zone rather than a single record set.
#
# Auth is certificate-based: the private key was generated on the NAS and
# never left it; only the public cert (nas-acme.crt) is registered here.
# ============================================================================

resource "azurerm_dns_zone" "home_acme" {
  name                = "home-acme.romaine.life"
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_dns_ns_record" "home_acme_delegation" {
  name                = "home-acme"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 3600
  records             = azurerm_dns_zone.home_acme.name_servers
}

resource "azurerm_dns_cname_record" "home_acme_challenge" {
  name                = "_acme-challenge.home"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  record              = "wildcard.${azurerm_dns_zone.home_acme.name}"
}

resource "azuread_application" "nas_acme" {
  display_name = "nas-acme"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "nas_acme" {
  client_id = azuread_application.nas_acme.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_certificate" "nas_acme" {
  application_id = azuread_application.nas_acme.id
  type           = "AsymmetricX509Cert"
  value          = file("${path.module}/nas-acme.crt")
  end_date       = "2036-09-26T00:00:00Z"
}

resource "azurerm_role_assignment" "nas_acme_dns" {
  scope                = azurerm_dns_zone.home_acme.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azuread_service_principal.nas_acme.object_id
}

output "nas_acme_client_id" {
  value = azuread_application.nas_acme.client_id
}
