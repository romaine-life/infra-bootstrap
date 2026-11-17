variable "cluster_subscription_id" {
  description = "Azure subscription ID for the AKS cluster and its VNet/subnet."
  type        = string
  default     = "606a1ca1-5833-4d21-8937-d0fcd97cd0a0"

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.cluster_subscription_id))
    error_message = "cluster_subscription_id must be an Azure subscription GUID."
  }
}

variable "cluster_resource_group_name" {
  description = "Resource group name for AKS cluster resources in the cluster subscription."
  type        = string
  default     = "infra"
}
