import {
  to = module.app_org["house-hunt"].github_repository.repo
  id = "house-hunt"
}

import {
  to = module.app_org["fzt-terminal"].github_repository.repo
  id = "fzt-terminal"
}

import {
  to = module.app_org["mcp-tank-operator"].github_repository.repo
  id = "mcp-tank-operator"
}

# mcp-auth: pre-created via `gh repo create` so the scaffold could land
# before this PR — see initial commit in nelsong6/mcp-auth. Tofu adopts
# the existing repo on next apply.
import {
  to = module.app_org["mcp-auth"].github_repository.repo
  id = "mcp-auth"
}
