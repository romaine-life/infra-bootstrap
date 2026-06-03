# Credentials for `infra-bootstrap-github-app` (app id 3942172), the GitHub App
# installed on the romaine-life org. Used by the (sole) `github` provider so
# org repo/secret/workflow management no longer depends on the personal PAT.
variable "github_app_id" {
  description = "App ID of infra-bootstrap-github-app (org-side github provider auth)."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID of infra-bootstrap-github-app on the romaine-life org."
  type        = string
}

variable "github_app_pem" {
  description = "PEM private key contents for infra-bootstrap-github-app."
  type        = string
  sensitive   = true
}

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
