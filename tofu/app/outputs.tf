output "service_principal_object_id" {
  value       = azuread_service_principal.app.object_id
  description = "Object ID of the app's Azure AD service principal — used by parent for ACR role grants, etc."
}

output "application_id" {
  value       = azuread_application.app.id
  description = "Application resource ID for additional CI identity federation."
}

output "client_id" {
  value       = azuread_application.app.client_id
  description = "The app's client id: its CI's ARM_CLIENT_ID, on GitHub and on Forgejo."
}
