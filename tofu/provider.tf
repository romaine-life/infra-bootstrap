terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    azapi = {
      source = "azure/azapi"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
# org-owned `infra-bootstrap-github-app` (app-auth). The personal nelsong6
# provider + PAT are retired now that all repos live in the org.
provider "github" {
  owner = "romaine-life"

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem
  }
}
