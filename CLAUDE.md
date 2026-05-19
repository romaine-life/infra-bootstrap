# infra-bootstrap

Root infrastructure repo. Creates shared Azure resources (tofu) and manages the AKS cluster platform (ArgoCD + GitOps).

## Architecture

Two layers:

- **`tofu/`** — OpenTofu managed by GitHub Actions CI. Creates AKS cluster, VNet, ACR, DNS zone, Cosmos DB, App Configuration, Key Vault references, managed identity, federated credentials, Entra app registrations. Plan on PR, apply on push to main.
- **`k8s/`** — Kubernetes manifests managed by ArgoCD. Everything deployed to the cluster lives here. ArgoCD auto-syncs from git.

### Kubernetes Layout

```
k8s/
  apps/              # ArgoCD Application manifests (one per component)
  argocd/            # Kustomize: Helm chart + ArgoCD-specific resources (cert, route, reference grant)
  cert-manager/      # Chart wrapper: subchart + ClusterIssuer template
  envoy-gateway/     # Chart wrapper: subchart + Gateway + GatewayClass templates
  external-dns/      # Chart wrapper: subchart + ExternalSecret for azure.json
  external-secrets/  # Chart wrapper: subchart + ClusterSecretStore template
  root-app.yaml      # App-of-apps (applied once by bootstrap, not self-managed)
```

### Chart Wrapper Pattern

Each component that needs config resources alongside its Helm chart gets a local wrapper: `Chart.yaml` declares the upstream chart as a dependency, `values.yaml` configures it, and `templates/` holds config resources (ClusterIssuer, ClusterSecretStore, Gateway, ExternalSecrets, etc.). ArgoCD points at the wrapper directory. Resources live alongside their concern.

### Secrets Flow

Tofu outputs → Key Vault → ExternalSecrets Operator → K8s Secrets. No manual `kubectl create secret`. The ClusterSecretStore (`romaine-kv`) uses workload identity on the shared managed identity.

### Bootstrap

The CI workflow (`tofu.yaml`) has a bootstrap job that runs once: installs ArgoCD via Kustomize (same definition ArgoCD uses to self-manage), creates repo/registry secrets, and applies the Application manifests. After first run, ArgoCD owns everything.

## Cluster Components

- **AKS** (`infra-aks`) — Free tier, two pools, Azure CNI Overlay, workload identity. **`system` pool**: 3× Standard_B2s_v2 (2 vCPU, 8 GiB) — original pool, still hosts the bulk of running workloads. **`user` pool**: 3× Standard_E2bs_v5 (2 vCPU, 16 GiB) — memory-optimized burstable, added to fix the per-node memory wall that tank-operator session pods kept hitting. No taints between pools; new pods land on the user pool because the system pool is full, and existing pods drain off the system pool as they end naturally. Both pools use 128 GiB OS disks. The split is intentional during migration; the system pool may shrink or get folded once the user pool absorbs steady-state workload.
- **ACR** (`romainecr`) — Basic SKU, AcrPull for kubelet identity
- **Envoy Gateway** — Gateway API controller + shared Gateway with HTTP/HTTPS listeners
- **ExternalDNS** — Azure DNS via workload identity, watches HTTPRoute resources
- **cert-manager** — Let's Encrypt HTTP-01 via Gateway API
- **ExternalSecrets** — ClusterSecretStore for Key Vault, workload identity
- **ArgoCD** — GitOps, dex SSO (Microsoft Entra), Kustomize self-management
- **ServerSideApply** — Default sync option for all apps (large CRDs, AKS-injected labels)

## App Onboarding

The app module (`tofu/app/main.tf`) creates per-app: GitHub repo, Azure AD app registration + service principal, OIDC federated credentials, and GitHub Actions variables. Setting `ci_only = true` skips web roles.

## Tofu → workflow wiring

For values produced by tofu that an internal workflow needs (SP client IDs, storage account names, secret URIs), use `output "x" { value = ... }` + `tofu output -raw x` at runtime against this repo's state. State stays the single source of truth, no drift between vars and reality, rotations don't need a tofu re-apply just to push the new value. App repos read the state by minting their CI SP an OIDC Azure token and granting it `Storage Blob Data Reader` on `nelsontofu/tfstate` (see e.g. `tofu/agent-screenshots.tf::glimmung_ci_tfstate_reader`); the workflow then runs `tofu init -backend-config=...` against the infra-bootstrap state and reads outputs. Avoid `github_actions_variable` for tofu-produced values — the only unavoidable exceptions are Tier-0 vars the workflow needs *before* it can `tofu init`: `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.

## SSO

Dex with Microsoft connector (`tenant: common`, any Microsoft account). Scopes: `openid profile email user.read`. RBAC maps email to admin role. Admin fallback via local credentials.

## Related Repos

- **infra-bootstrap** (this repo) — root infrastructure + cluster platform
- **my-homepage**, **kill-me**, **plant-agent**, **investing**, **house-hunt**, **fzt-frontend**, **diagrams**, **llm-explorer**, **ambience**, **tank-operator**, **glimmung** — apps on AKS (each namespace + Deployment + HTTPRoute)
- **bender-world**, **eight-queens**, **lights**, **fzt-showcase**, **landing-page** — frontend-only SWAs (intentional, kept as SWAs)
- **pipeline-templates** — reusable GitHub Actions workflows

## Historical Notes

- The shared `api` repo hosted every app's backend routes until 2026-04-20; each app now owns its own K8s Deployment with inline routes. api repo is archived.
- Static Web Apps used to be the default hosting; apps that need backends migrated to AKS. SWAs remain for intentionally frontend-only apps.
- The shared Container App Environment (`infra-aca`) was decommissioned 2026-04-20 — all apps moved to AKS.
