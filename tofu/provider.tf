terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    azuread = {
      source = "hashicorp/azuread"
    }
    github = {
      source = "integrations/github"
    }
    azapi = {
      source = "azure/azapi"
    }
    random = {
      source = "hashicorp/random"
    }
    # forgejo-variables.tf: the apps' Forgejo Actions variables, signed in by the job's token.
    # Nelson's fork of svalabs/forgejo (romaine-life/terraform-provider-forgejo), which adds
    # import for forgejo_repository_action_variable; published to Artifact Keeper.
    forgejo = {
      source = "artifacts.home.romaine.life/romaine-life/forgejo"
    }
    external = {
      source = "hashicorp/external"
    }
  }
  backend "azurerm" {
    resource_group_name  = "infra"
    storage_account_name = "nelsontofu"
    container_name       = "tfstate"
    key                  = "infra-bootstrap.tfstate"
    use_oidc             = true
  }
}

provider "azurerm" {
  features {}
  use_oidc                        = true
  resource_provider_registrations = "none"
}

provider "azurerm" {
  alias = "cluster"

  features {}
  use_oidc                        = true
  subscription_id                 = var.cluster_subscription_id != "" ? var.cluster_subscription_id : null
  resource_provider_registrations = "none"
}

provider "azuread" {
  use_oidc = true
}

# Single GitHub provider for the romaine-life org, authenticating as the
# org-owned `infra-bootstrap-github-app` (app id 3942172, app-auth). Its
# credentials are read from romaine-kv as ephemeral values, so they stay out of
# the state and the plan.
ephemeral "azurerm_key_vault_secret" "github_app" {
  for_each = toset(["id", "installation-id", "private-key"])

  name         = "infra-bootstrap-github-app-${each.key}"
  key_vault_id = data.azurerm_key_vault.main.id
}

provider "github" {
  owner = "romaine-life"

  app_auth {
    id              = ephemeral.azurerm_key_vault_secret.github_app["id"].value
    installation_id = ephemeral.azurerm_key_vault_secret.github_app["installation-id"].value
    pem_file        = ephemeral.azurerm_key_vault_secret.github_app["private-key"].value
  }
}
