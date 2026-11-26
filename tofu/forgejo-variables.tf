# Each app whose CI runs on Forgejo gets its Azure sign-in as Forgejo Actions variables,
# ARM_CLIENT_ID, ARM_TENANT_ID and ARM_SUBSCRIPTION_ID: the same values the app module
# writes on its GitHub copy. Before this they were set on Forgejo by hand, per repo (PG-1).
#
# tofu signs in to Forgejo with no stored secret: this CI job's own short-lived token
# (forgejo-job-token.sh), taken by one of nelson's authorized integrations, made once with
# Forgejo's CLI (nelsong6/forgejo README, Package sign-in): `infra-bootstrap-tofu`
# (write:repository) for tofu/ci.yml on a push or dispatch of main, `infra-bootstrap-tofu-plan`
# (read:repository) for its pull requests' plans.
#
# A repo's variables set by hand before it joined are adopted by the import blocks below, not
# deleted: the provider refuses to create a variable that already exists.

data "external" "forgejo_job" {
  program = ["sh", "${path.module}/forgejo-job-token.sh"]
  query = {
    forgejo_apply_audience = "u:1:54c9ebdc-ed00-49ca-a319-7ab02a623ed1"
    forgejo_plan_audience  = "u:1:4e5c47dd-2f17-4eec-90dc-b8e40def3eb9"
  }
}

provider "forgejo" {
  host      = "https://forgejo.romaine.life"
  api_token = data.external.forgejo_job.result.forgejo_jwt
}

provider "svalabs-forgejo" {
  host      = "https://forgejo.romaine.life"
  api_token = data.external.forgejo_job.result.forgejo_jwt
}

locals {
  # Every app module repository whose CI runs on Forgejo (forgejo-ci.tf).
  forgejo_variable_apps = setunion(local.forgejo_ci_apps, ["terminal-share", "pokemon-generator", "pokosmari", "dungeon-crawler"])

  # The repositories whose variables were set by hand before tofu wrote them (IB-3). tank-operator
  # had none on Forgejo, so tofu creates its.
  forgejo_variable_imports = setsubtract(local.forgejo_variable_apps, ["pokosmari", "dungeon-crawler", "tank-operator"])

  forgejo_variables = merge([
    for app in local.forgejo_variable_apps : {
      for name, value in {
        ARM_CLIENT_ID       = module.app_org[app].client_id
        ARM_TENANT_ID       = data.azurerm_client_config.current.tenant_id
        ARM_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
      } : "${app}/${name}" => { app = app, name = name, value = value }
    }
  ]...)
}

data "forgejo_repository" "app" {
  for_each = local.forgejo_variable_apps
  owner    = "romaine-life"
  name     = each.key
}

resource "forgejo_repository_action_variable" "app" {
  for_each      = local.forgejo_variables
  repository_id = data.forgejo_repository.app[each.value.app].id
  name          = each.value.name
  data          = each.value.value
}

import {
  for_each = { for key, v in local.forgejo_variables : key => v if contains(local.forgejo_variable_imports, v.app) }
  to       = forgejo_repository_action_variable.app[each.key]
  id       = "romaine-life/${each.key}"
}
