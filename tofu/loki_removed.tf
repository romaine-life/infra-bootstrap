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
