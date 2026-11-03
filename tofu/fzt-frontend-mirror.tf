# FORGEJO-6: fzt-frontend runs at home. Keep only the GitHub push-mirror
# repository; removing its app module retires the Azure CI registration and grants.
# The move preserves its identity and contents, and ignore_changes avoids resetting
# the mirror's Actions/settings through the old app-vending defaults.
moved {
  from = module.app_org["fzt-frontend"].github_repository.repo
  to   = github_repository.fzt_frontend_mirror
}

resource "github_repository" "fzt_frontend_mirror" {
  name       = "fzt-frontend"
  visibility = "public"
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
