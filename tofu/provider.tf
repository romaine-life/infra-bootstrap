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

provider "github" {
  owner = var.github_owner
  token = var.github_pat
}

provider "github" {
  alias = "romaine_life"
  owner = "romaine-life"

  # Org-side writes authenticate as the dedicated `infra-bootstrap-github-app`
  # (installed on the romaine-life org) instead of the personal PAT. The PAT
  # remains on the default provider above only until the personal_apps are
  # migrated/retired and TF_VAR_github_owner can flip.
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem
  }
}
