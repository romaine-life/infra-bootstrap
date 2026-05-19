# The live `system` node pool is now the cluster default_node_pool. Forget the
# old standalone node-pool state address without deleting the live pool.

removed {
  from = azurerm_kubernetes_cluster_node_pool.cluster_system

  lifecycle {
    destroy = false
  }
}
