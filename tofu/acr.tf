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
# Scheduled purge to reclaim registry storage.
# ----------------------------------------------------------------------------
# Basic SKU includes ~10 GiB; overage is billed per-GiB/day. Without active
# reclamation the registry grew to ~655 GiB (~$58/mo overage). The root causes,
# and what each step below addresses:
#
#   1. `*-build-cache` repos — regenerable BuildKit layer sets, by far the
#      biggest sink (one cache repo alone held >1,600 manifests). Trimmed hard.
#   2. Untagged ("dangling") manifests — left behind whenever a tag is moved or
#      an alias is deleted. The previous task NEVER passed `--untagged`, so these
#      accumulated forever. `acr purge --untagged` won't orphan manifests still
#      referenced by a tagged multi-arch index, so it is safe registry-wide.
#   3. Stale per-commit image history (`app-<sha256>`, bare-sha, `sha-<commit>`
#      resolver aliases) — one+ per build, previously kept indefinitely.
#
# IMPORTANT — why this won't delete a live image: `--keep N` always retains the
# N newest tags of each repo regardless of age, and a running deployment pins its
# image by the newest tag it pushed. The only edge case is an app pinned to an
# OLD image (a manual rollback) that also has >N newer untouched builds; keep N
# generous (10) to make that effectively impossible for these low-churn repos.
#
# docker-build-check still publishes commit-addressed `sha-<commit>` / `ci-*`
# aliases for Glimmung's deploy-image resolver; step 2's 30d window is far longer
# than any ephemeral test-slot lease, so no live slot loses its alias.
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
        # 1) BuildKit caches: keep a few recent manifests so builds still warm-
        #    start, drop the rest. This is the largest single reclaim.
        - cmd: acr purge --filter '.*-build-cache:.*' --ago 7d --keep 3 --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
        # 2) Ephemeral CI resolver aliases + the orphaned manifests they leave
        #    behind (the --untagged that was missing before).
        - cmd: acr purge --filter '.*:^sha-[0-9a-f]+$' --filter '.*:^ci-(pr|ref)-.+' --ago 30d --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
        # 3) Trim stale image history registry-wide, keeping the 10 newest builds
        #    of every repo for rollback, and sweep any remaining dangling layers.
        - cmd: acr purge --filter '.*:.*' --ago 30d --keep 10 --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
    YAML
    )
  }
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
  # `app-`/`claude-`/`api-proxy-`/etc. (Basic SKU caps webhooks at 2 — first one.)
  scope  = ""
  status = "enabled"

  custom_headers = {
    "Authorization" = "Bearer ${random_password.tank_acr_webhook.result}"
  }
}
