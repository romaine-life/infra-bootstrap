# ============================================================================
# Azure Container Registry (ACR)
# ============================================================================
# Shared container registry for all app images. AKS pulls images via the
# kubelet identity's AcrPull role — no image pull secrets needed.
# ============================================================================

resource "azurerm_container_registry" "main" {
  name                = "romainecr"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Grant AcrPull to the AKS kubelet identity so nodes can pull images
resource "azurerm_role_assignment" "cluster_aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.cluster.kubelet_identity[0].object_id
}

moved {
  from = azurerm_role_assignment.cluster_aks_acr_pull[0]
  to   = azurerm_role_assignment.cluster_aks_acr_pull
}

# AcrPush for each k8s-migrated app's service principal. CI uses the SP (via
# OIDC) to `az acr login` and `docker push` its image during build-and-deploy.
# Subscription-scoped Contributor doesn't cover dataActions, so AcrPush must
# be granted explicitly.
resource "azurerm_role_assignment" "app_acr_push" {
  for_each             = local.k8s_apps
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = local.app_service_principal_object_ids[each.key]
}

# ----------------------------------------------------------------------------
# Scheduled purge of ephemeral CI lookup aliases.
# ----------------------------------------------------------------------------
# docker-build-check publishes a commit-addressed `sha-<commit>` alias (and,
# historically, run-scoped `ci-pr-`/`ci-ref-` tags) so Glimmung's deploy-image
# resolver can look a test-slot image up by the verified commit SHA. These
# aliases accrue ~1 per build and are NEVER referenced by Helm charts — charts
# pin the content fingerprint `app-<sha256>`. The alias is just a second tag on
# that same manifest, so deleting the alias tag leaves the fingerprint image
# intact.
#
# The filters match ONLY `sha-<hex>` and `ci-(pr|ref)-` tags (anchored), never
# `app-`/`claude-`/`codex-`/`api-proxy-` images. `--ago 30d` is far longer than
# any ephemeral test-slot lease, so no live slot can reference a purged alias.
resource "azurerm_container_registry_task" "purge_ci_aliases" {
  name                  = "purge-ci-aliases"
  container_registry_id = azurerm_container_registry.main.id

  platform {
    os = "Linux"
  }

  timer_trigger {
    name     = "weekly"
    schedule = "0 4 * * Sun"
  }

  encoded_step {
    task_content = base64encode(<<-YAML
      version: v1.1.0
      steps:
        - cmd: acr purge --filter '.*:^sha-[0-9a-f]+$' --filter '.*:^ci-(pr|ref)-.+' --ago 30d
          disableWorkingDirectoryOverride: true
          timeout: 3600
    YAML
    )
  }
}
