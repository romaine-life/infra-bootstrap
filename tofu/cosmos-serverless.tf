# ============================================================================
# Shared serverless Cosmos DB account
# ============================================================================
# Replaces the previous provisioned free-tier `infra-cosmos` account (torn
# down 2026-04-20). The old account had apps' tofus declaring DBs with no
# throughput specified, which caused Azure to default every container to a
# dedicated 400 RU/s offer — twelve idle offers ran the bill to ~$100/mo.
#
# Serverless fits the actual usage pattern: pay-per-request, no idle floor,
# no per-container cost. It is mutually exclusive with free tier and with
# provisioned throughput at any scope, so a new account was required —
# accounts cannot be converted in-place between the offer flavours.

resource "azurerm_cosmosdb_account" "serverless" {
  name                = "infra-cosmos-serverless"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Serverless capability — mutually exclusive with free tier and with
  # provisioned throughput at database/container scope.
  capabilities {
    name = "EnableServerless"
  }

  free_tier_enabled          = false
  automatic_failover_enabled = false

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = data.azurerm_resource_group.main.location
    failover_priority = 0
  }

  # Point-in-time restore instead of the Periodic default (240-minute
  # interval / 8-hour retention / Geo redundancy), which kept at most two
  # backups alive and made restore an Azure support ticket rather than a
  # self-service operation.
  #
  # ONE-WAY: Azure does not support migrating an account back from
  # Continuous to Periodic. Don't try to revert this block — the provider
  # and ARM will both reject it, and the account would have to be rebuilt.
  # `Continuous7Days` costs nothing to store — only the 30/35-day tiers are
  # billed for backup storage ($0.20/GB/region/month). Restores are billed
  # on every tier. Switching *between* continuous tiers is allowed, so
  # `Continuous30Days` stays available if 7 days ever proves too short.
  backup {
    type = "Continuous"
    tier = "Continuous7Days"
  }
}

# Cosmos data plane role on the shared identity used to be assigned here
# at *account* scope — every opted-in app could read every other app's
# data. Removed once every app moved to its own per-app identity with a
# narrowed `dbs/<name>` scope (kill-me/tofu/identity.tf,
# plant-agent/tofu/identity.tf, glimmung/tofu/identity.tf, and the rest).
# Don't re-add this assignment — narrow per-app scopes are the convention
# now.

