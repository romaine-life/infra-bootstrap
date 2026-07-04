# ============================================================================
# AKS — chess-tactics trainer node pool
# ============================================================================
# A dedicated, scale-to-zero user pool for the chess-tactics AI training jobs
# (SPSA self-play tuning + SPRT validation). Training is bursty and CPU-bound:
# a run pins all cores for ~1-3h, then nothing until the next run. Running it in
# the always-on `system` pool (a single 2 vCPU B2s_v2) is impossible — there is
# no spare CPU — and pinning a big node 24/7 would be pure waste.
#
# So: an autoscaling User pool with min_count = 0. It holds ZERO nodes (and costs
# nothing) at idle; when the backend creates a training Job that tolerates the
# taint below, the cluster autoscaler provisions one node, runs the job, and
# scales back to zero when it completes.
#
# SKU choice (2026-07, westus2, romaine-life sub): Standard_FSv2 was the natural
# compute-optimized pick but is capacity-constrained ("only available in Denmark")
# and its quota increase was refused; the whole Dsv5/Dasv5 v5 line is at 0 quota.
# Standard_D8als_v7 (AMD Genoa, 8 vCPU / 16 GiB) is OPEN for the sub AND fits the
# existing Dalsv7 family quota (10 vCPU) with NO quota increase required — 8 <= 10.
# Compute-appropriate, cheapest available (~$0.32/hr on-demand), and the tiny
# self-play engine (48 KB bundle) needs almost no RAM. max_count is 1 because a
# second 8-vCPU node would need 16 vCPU of quota (> 10); bump the Dalsv7 quota and
# raise max_count to run tunes concurrently.
resource "azurerm_kubernetes_cluster_node_pool" "chess_trainer" {
  provider = azurerm.cluster

  name                  = "trainer"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  vm_size               = "Standard_D8als_v7"
  os_disk_size_gb       = 32
  vnet_subnet_id        = azurerm_subnet.cluster_aks_nodes.id
  mode                  = "User"

  # Scale-to-zero: no node until a training Job is pending, none after it ends.
  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 1

  # Only the trainer Jobs land here. They set a matching nodeSelector + toleration
  # (k8s chart); every other workload lacks the toleration, so this pool stays
  # empty — and therefore scaled to zero — except during a run. The label is the
  # nodeSelector target; the taint is the fence.
  node_labels = { workload = "trainer" }
  node_taints = ["workload=trainer:NoSchedule"]

  # Match the system pool's declared upgrade settings so tofu sees no drift and
  # never tries to unset undrainable_node_behavior (which forces cluster replace).
  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
    undrainable_node_behavior     = "Schedule"
  }

  lifecycle {
    ignore_changes = [node_count] # owned by the autoscaler, not tofu
  }
}
