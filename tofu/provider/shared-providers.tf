terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.70.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.8.0"
    }
    github = {
      source  = "integrations/github"
      version = "= 6.12.1"
    }
    azapi = {
      source  = "azure/azapi"
      version = "= 2.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }
}
