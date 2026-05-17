# ============================================================================
# State moves — parent → web extractions kept while the target resources
# still live in `tofu/app/web/main.tf`. Each block tells OpenTofu that an
# existing state object has a new address.
# ============================================================================

moved {
  from = azurerm_role_assignment.appconfig_data_owner
  to   = module.web[0].azurerm_role_assignment.appconfig_data_owner
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
