# ============================================================================
# State moves — resources extracted from this module into the web sub-module.
# These tell OpenTofu where existing state objects now live.
# ============================================================================

moved {
  from = azurerm_role_assignment.contributor
  to   = module.web[0].azurerm_role_assignment.contributor
}

moved {
  from = azurerm_role_assignment.rbac_admin
  to   = module.web[0].azurerm_role_assignment.rbac_admin
}

moved {
  from = azurerm_role_assignment.keyvault_secrets_officer
  to   = module.web[0].azurerm_role_assignment.keyvault_secrets_officer
}

moved {
  from = azurerm_role_assignment.appconfig_data_owner
  to   = module.web[0].azurerm_role_assignment.appconfig_data_owner
}

moved {
  from = azurerm_role_assignment.storage_blob_reader
  to   = module.web[0].azurerm_role_assignment.storage_blob_reader
}

moved {
  from = azurerm_cosmosdb_sql_role_assignment.cosmos_data_reader
  to   = module.web[0].azurerm_cosmosdb_sql_role_assignment.cosmos_data_reader
}

moved {
  from = azuread_app_role_assignment.app_readwrite_owned
  to   = module.web[0].azuread_app_role_assignment.app_readwrite_owned
}

moved {
  from = azuread_application_federated_identity_credential.github_actions_prod
  to   = module.web[0].azuread_application_federated_identity_credential.github_actions_prod
}

moved {
  from = github_actions_variable.google_client_id
  to   = module.web[0].github_actions_variable.google_client_id
}

# ============================================================================
# Reverse moves — resources extracted from the web sub-module back into the
# parent module, now gated on opt-in booleans so ci_only apps can use them.
# ============================================================================
#
# Each pair pulls a resource out of `module.web[0]` and back to the parent
# address with a `count` index, paired with the corresponding `var.<flag>`
# in main.tf. State migrations are no-ops in Azure when the flag is true
# for the same set of apps that previously had ci_only = false; they
# only manifest as creates for newly-opted-in ci_only apps.

moved {
  from = module.web[0].azurerm_role_assignment.storage_blob_contributor
  to   = azurerm_role_assignment.storage_blob_contributor[0]
}

moved {
  from = module.web[0].github_actions_variable.tfstate_storage_account
  to   = github_actions_variable.tfstate_storage_account[0]
}
