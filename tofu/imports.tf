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
# before this PR — see initial commit in romaine-life/mcp-auth. Tofu adopts
# the existing repo on next apply.
import {
  to = module.app_org["mcp-auth"].github_repository.repo
  id = "mcp-auth"
}

# mcp-grafana: pre-created so the MCP scaffold could land before the
# infra-bootstrap PR adopts the repo into the per-app module.
import {
  to = module.app_org["mcp-grafana"].github_repository.repo
  id = "mcp-grafana"
}
