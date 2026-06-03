# ============================================================================
# `removed` blocks: drop app-specific identity resources from this state
# ============================================================================
# Companion to romaine-life/fzt-frontend#9 and romaine-life/llm-explorer#4, both
# of which import the same Azure resources into their own per-repo tofu
# state. With `lifecycle.destroy = false` the Azure resources stay in
# place — only this state forgets they exist.
#
# These blocks are scaffolding. Once main has applied successfully and we
# confirm the resources are owned only by the per-repo states (and that
# nothing in this state still references them), this whole file can be
# deleted in a follow-up PR.
#
# Why this exists at all: app-specific resources don't belong in shared
# infra-bootstrap state. The precipitating case was mcp-azure-personal —
# see romaine-life/infra-bootstrap#127 and #128. fzt-frontend and llm-explorer
# were acknowledged anti-patterns at the time (the deleted files' headers
# literally said "should move when those apps grow tofu pipelines"); now
# they do.
# ============================================================================

# ----------------------------------------------------------------------------
# fzt-frontend — moved to romaine-life/fzt-frontend/infra/
# ----------------------------------------------------------------------------

removed {
  from = azurerm_user_assigned_identity.fzt_frontend
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_cosmosdb_sql_role_assignment.fzt_frontend_cosmos
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_role_assignment.fzt_frontend_kv_jwt_secret
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_role_assignment.fzt_frontend_appconfig
  lifecycle {
    destroy = false
  }
}

# Only the dedicated-cluster FIC is in state; the same-sub variant had
# `count = local.cluster_uses_dedicated_subscription ? 0 : 1` and has
# never been live.
removed {
  from = azurerm_federated_identity_credential.cluster_fzt_frontend
  lifecycle {
    destroy = false
  }
}

# ----------------------------------------------------------------------------
# llm-explorer — moved to romaine-life/llm-explorer/infra/
# ----------------------------------------------------------------------------

removed {
  from = azurerm_user_assigned_identity.llm_explorer
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_cosmosdb_sql_role_assignment.llm_explorer_cosmos
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_role_assignment.llm_explorer_kv_jwt_secret
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_role_assignment.llm_explorer_appconfig
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_federated_identity_credential.cluster_llm_explorer
  lifecycle {
    destroy = false
  }
}
