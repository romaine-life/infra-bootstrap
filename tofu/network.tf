# ============================================================================
# Networking
# ============================================================================
# VNet and subnet for AKS. Address space is intentionally large (/16) to
# leave room for future subnets (Bastion, private endpoints, etc.).
# The AKS subnet uses /22 (1024 addresses) — with Azure CNI Overlay only
# node IPs consume subnet addresses, not pod IPs.
# ============================================================================

resource "azurerm_virtual_network" "main" {
  name                = "infra-vnet"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/22"]
}

resource "azurerm_virtual_network" "cluster" {
  provider = azurerm.cluster

  name                = "infra-vnet"
  resource_group_name = local.cluster_resource_group_name
  location            = local.cluster_resource_group_location
  address_space       = ["10.0.0.0/16"]
}

moved {
  from = azurerm_virtual_network.cluster[0]
  to   = azurerm_virtual_network.cluster
}

resource "azurerm_subnet" "cluster_aks_nodes" {
  provider = azurerm.cluster

  name                 = "aks-nodes"
  resource_group_name  = local.cluster_resource_group_name
  virtual_network_name = azurerm_virtual_network.cluster.name
  address_prefixes     = ["10.0.0.0/22"]
}

moved {
  from = azurerm_subnet.cluster_aks_nodes[0]
  to   = azurerm_subnet.cluster_aks_nodes
}
