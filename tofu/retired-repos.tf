# Repos retained after their deployed projects were torn down.
#
# emma-birthday's Kubernetes app, Azure app registration, role assignments, and
# GitHub Actions variables were removed during teardown. The workflow identity
# does not have GitHub repository admin/delete rights, so keep the code repo
# managed here instead of retrying an impossible delete from the old app module.
moved {
  from = module.app["emma-birthday"].github_repository.repo
  to   = github_repository.retired["emma-birthday"]
}

resource "github_repository" "retired" {
  for_each = toset([
    "emma-birthday",
  ])

  name       = each.key
  visibility = "public"
  auto_init  = true
  topics     = []

  has_issues = true

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  delete_branch_on_merge = true

  lifecycle {
    prevent_destroy = true
  }
}
