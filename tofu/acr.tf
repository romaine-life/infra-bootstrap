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
  sku                 = "Standard"
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

# Scheduled purge of stale images and BuildKit cache manifests.
# ----------------------------------------------------------------------------
# Delete BuildKit cache repositories entirely, then keep the three newest
# tagged manifests per image repository and delete untagged leftovers. Do not
# use an age gate here: high-churn repos can create hundreds of manifests
# inside a week, so `--ago 7d`/`--ago 30d` still lets ACR storage balloon.
# Deployed images are expected to be one of the newest tags for their app repo.
resource "azurerm_container_registry_task" "purge_stale_images" {
  name                  = "purge-stale-images"
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
        - cmd: acr purge --filter '.*-build-cache:.*' --ago 0d --keep 0 --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
        - cmd: acr purge --filter '.*:.*' --ago 0d --keep 3 --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
    YAML
    )
  }
}

moved {
  from = azurerm_container_registry_task.purge_ci_aliases
  to   = azurerm_container_registry_task.purge_stale_images
}

# ----------------------------------------------------------------------------
# Image-readiness webhook → tank-operator (event-driven provisioning signal).
# ----------------------------------------------------------------------------
# ACR fires a `push` delivery the instant a `sha-<commit>` image tag lands in
# the registry. tank-operator's POST /webhooks/acr receiver records it as the
# durable "the deployable image for this commit now exists" signal, which
# replaces the test-slot provisioning gate's image-build *polling* wait (see
# docs/event-driven-rollout.md in romaine-life/tank-operator). No more racing a
# poller against registry propagation — the registry itself reports the instant
# the artifact is queryable.
#
# Auth is a static bearer secret, and tofu owns BOTH ends of it: the same
# generated value is stored in romaine-kv as `tank-operator-acr-webhook-secret`
# (mirrored to the orchestrator as ACR_WEBHOOK_SECRET via ESO) AND sent as the
# webhook's Authorization header — so the two never drift and there is no manual
# seed. The receiver fails closed on an empty secret.
resource "random_password" "tank_acr_webhook" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "tank_acr_webhook" {
  name         = "tank-operator-acr-webhook-secret"
  value        = random_password.tank_acr_webhook.result
  key_vault_id = data.azurerm_key_vault.main.id
}

resource "azurerm_container_registry_webhook" "tank_ci_image" {
  name                = "tankciimage"
  resource_group_name = data.azurerm_resource_group.main.name
  registry_name       = azurerm_container_registry.main.name
  location            = data.azurerm_resource_group.main.location
  service_uri         = "https://tank.romaine.life/webhooks/acr"
  actions             = ["push"]

  # Registry-wide; the receiver filters to `sha-<commit>` tags and ignores
  # `app-`/`claude-`/`api-proxy-`/etc.
  scope  = ""
  status = "enabled"

  custom_headers = {
    "Authorization" = "Bearer ${random_password.tank_acr_webhook.result}"
  }
}
