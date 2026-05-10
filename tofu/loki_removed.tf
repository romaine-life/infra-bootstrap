removed {
  from = azurerm_storage_account.loki

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_storage_container.loki

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_user_assigned_identity.loki

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_role_assignment.loki_storage_blob_contributor

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_federated_identity_credential.loki

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_federated_identity_credential.cluster_loki

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_actions_variable.loki_identity_client_id

  lifecycle {
    destroy = false
  }
}
