# The romaine-life subscription and card-utility-stats dev VNet were deleted
# after the Slay the Spire image-building experiment was abandoned. Forget the
# old cross-subscription peering objects without trying to call the deleted
# subscription during plan/apply.

removed {
  from = azurerm_role_assignment.romaine_life_network_contributor
}

removed {
  from = azurerm_virtual_network_peering.infra_to_romaine_life_card_utility_stats_dev
}

removed {
  from = azurerm_virtual_network_peering.romaine_life_card_utility_stats_dev_to_infra
}

# Ambience owns its user-auth app registration from nelsong6/ambience/tofu.
# Forget the old shared-infra state entries without deleting the live Entra app
# or its published Key Vault client-id secret.

removed {
  from = azuread_application.ambience_oauth
}

removed {
  from = azuread_service_principal.ambience_oauth
}

removed {
  from = azurerm_key_vault_secret.ambience_oauth_client_id
}

# OSMS owns Loki storage and workload identity from nelsong6/osms/tofu.
# Forget the old shared-infra state entries without deleting the live storage
# account, containers, identity, role assignment, or GitHub variable.

removed {
  from = azurerm_storage_account.loki
}

removed {
  from = azurerm_storage_container.loki
}

removed {
  from = azurerm_user_assigned_identity.loki
}

removed {
  from = azurerm_role_assignment.loki_storage_blob_contributor
}

removed {
  from = azurerm_federated_identity_credential.loki
}

removed {
  from = azurerm_federated_identity_credential.cluster_loki
}

removed {
  from = github_actions_variable.loki_identity_client_id
}

# emma-birthday has been torn down. The workflow identity can remove the
# Kubernetes app, Azure app registration, role assignments, and repo variables,
# but it does not have GitHub repository admin/delete rights. Forget the
# remaining repository state entry instead of retrying an impossible delete.
removed {
  from = module.app["emma-birthday"].github_repository.repo

  lifecycle {
    destroy = false
  }
}
