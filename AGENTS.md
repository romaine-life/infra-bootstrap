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

Tofu outputs → Key Vault → ExternalSecrets Operator → K8s Secrets. No manual `kubectl create secret`. `romaine-kv` is the platform/shared store; app-owned secrets belong in Key Vaults provisioned by the app repos, with matching External Secrets stores defined alongside the app chart. CI app registrations created here get subscription-scope Key Vault Administrator in both the workload and cluster subscriptions.

### Bootstrap

The CI workflow (`tofu.yaml`) has a bootstrap job that runs once: installs ArgoCD via Kustomize (same definition ArgoCD uses to self-manage), creates repo/registry secrets, and applies the Application manifests. After first run, ArgoCD owns everything.

## Cluster Components

- **AKS** (`infra-aks`) — Free tier, system-mode pool is `system` at 3x Standard_E2bs_v5 (2 vCPU, 16 GiB RAM each) with 128 GiB OS disks, Azure CNI Overlay, workload identity.
- **ACR** (`romainecr`) — Basic SKU, AcrPull for kubelet identity
- **Envoy Gateway** — Gateway API controller + shared Gateway with HTTP/HTTPS listeners
- **ExternalDNS** — Azure DNS via workload identity, watches HTTPRoute resources
- **cert-manager** — Let's Encrypt HTTP-01 via Gateway API
- **ExternalSecrets** — ClusterSecretStore for Key Vault, workload identity
- **ArgoCD** — GitOps, native OIDC SSO direct to auth.romaine.life (no Dex), Kustomize self-management
- **ServerSideApply** — Default sync option for all apps (large CRDs, AKS-injected labels)

## App Onboarding

The app module (`tofu/app/main.tf`) creates per-app: GitHub repo, Azure AD app registration + service principal, OIDC federated credentials, and GitHub Actions variables. Setting `ci_only = true` skips web roles.

## SSO

ArgoCD authenticates humans as a **native OIDC relying party** directly to **auth.romaine.life** (`oidc.config`, public client + PKCE via `enablePKCEAuthentication`, no client secret — same shape as Grafana). auth.romaine.life is the single source of truth for who gets in across every romaine.life app; it mirrors each user's platform `role` into a `groups` claim on the id_token, and ArgoCD RBAC maps `g, admin, role:admin`. The in-cluster **mcp-argocd** server authenticates to the ArgoCD API with an auth.romaine.life `role=service` JWT (minted via `/api/auth/exchange/k8s`, `sub=svc:mcp-argocd:mcp-argocd`), verified through the same `oidc.config` provider and mapped to `role:mcp-argocd` — so `scopes: '[groups, sub]'`. **Dex is fully retired** (`dex.enabled: false`); both humans and mcp-argocd go straight to auth.romaine.life. Grant/revoke admin by changing a user's role in auth.romaine.life — there is no email list in this repo. Admin fallback via local credentials.

## Related Repos

- **infra-bootstrap** (this repo) — root infrastructure + cluster platform
- **my-homepage**, **kill-me**, **plant-agent**, **investing**, **house-hunt**, **fzt-frontend**, **diagrams**, **llm-explorer**, **ambience**, **tank-operator**, **glimmung** — apps on AKS (each namespace + Deployment + HTTPRoute)
- **bender-world**, **eight-queens**, **lights**, **fzt-showcase**, **landing-page** — frontend-only SWAs (intentional, kept as SWAs)
- **pipeline-templates** — reusable GitHub Actions workflows

## Historical Notes

- The shared `api` repo hosted every app's backend routes until 2026-04-20; each app now owns its own K8s Deployment with inline routes. api repo is archived.
- Static Web Apps used to be the default hosting; apps that need backends migrated to AKS. SWAs remain for intentionally frontend-only apps.
- The shared Container App Environment (`infra-aca`) was decommissioned 2026-04-20 — all apps moved to AKS.
