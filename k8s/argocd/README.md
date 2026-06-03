# ArgoCD GitHub App

ArgoCD uses a dedicated org-owned GitHub App for repository credentials and
push webhooks. This app is separate from `infra-bootstrap-github-app`, from
Tank's host app, and from app-specific runtime apps such as Glimmung.

Key Vault secrets in `ng6-argocd`:

- `argocd-github-app-id`
- `argocd-github-app-installation-id`
- `argocd-github-app-private-key`
- `argocd-github-webhook-secret`

Create the app through the GitHub App manifest flow. Do not rely on settings
page query parameters for webhook events; GitHub can ignore them silently.

```json
{
  "name": "romaine-life-argocd",
  "url": "https://argocd.romaine.life",
  "hook_attributes": {
    "url": "https://argocd.romaine.life/api/webhook"
  },
  "redirect_url": "http://localhost:9/github-app-manifest-callback",
  "public": false,
  "default_permissions": {
    "contents": "read",
    "metadata": "read"
  },
  "default_events": [
    "push"
  ]
}
```

Install it on the `romaine-life` organization, all repositories. After
creation, write the app id, installation id, and private key into the Key Vault
secrets above, and set the app webhook secret to the value in
`argocd-github-webhook-secret`.
