# apps

One directory per application.

Each holds an Argo CD `Application` pointing at the OCI chart the application
repository publishes, pinned to an immutable version, plus its production values
([ADR 0011](../../docs/adr/0011-artifact-distribution-ghcr.md)).

Its `SealedSecret`s live in the same directory, on an earlier sync wave than the
Application that consumes them — the same shape as
[`../platform`](../platform/README.md), and for the same reason: on a rebuild
every seal is stale, and the wave should stop there rather than let the
application deploy into a cluster where its `DATABASE_URL` does not exist.

The failure modes are worth knowing apart:

| Stale | Symptom |
|---|---|
| the application's own `SealedSecret` | wave stops, `SealedSecret` Degraded with the controller's message |
| the GHCR registry credential (#10, in `platform/`) | the Application cannot render its chart — a *source* error, not a health one |

Adding a second service is a directory here — no Terraform, no cloud
credentials. That is the property [ADR 0006](../../docs/adr/0006-gitops-argo-cd-app-of-apps.md)
is buying.

## heptapedal

| Wave | What |
|---|---|
| -1 | `hepta` namespace |
| 0 | `app-secrets`, `agent-auth-secrets`, and the `ghcr` pull credential |
| 1 | `heptapedal-embeddings` — the app reaches it at `embeddings.hepta.svc:80` |
| 2 | `heptapedal-app` |

Each Application pins an immutable chart version rather than a moving tag
([ADR 0011](../../docs/adr/0011-artifact-distribution-ghcr.md)). The two charts
are released independently — the application's moves without the embeddings
service's — so their versions need not match, and are not restated here. The
published charts already point `image.repository`/`tag` at GHCR, so the values
here do not restate them.

### Why the Secret's wave is not merely tidy

The chart's migration Job is a Helm hook (`pre-install,pre-upgrade`), which Argo
CD runs as **PreSync** — before the Application's own resources exist. Both it
and the Deployment take the whole Secret with `envFrom`, so the Job reads
`DATABASE_URL` from a Secret that its own sync has not created and never will.

The Secret therefore has to be in place before the child Application starts
syncing at all. Putting it in *this* bundle at wave 0, with the Application at
wave 1, is what arranges that: waves here are the parent's, so wave 0 completes
— the `SealedSecret` decrypted and reporting healthy — before the Application
resource is even created.

Sealing it into the application's own directory would be too late, because by
then PreSync has already run.

### Sealing it

Keys become environment variable names verbatim, because both pod specs use
`envFrom: secretRef` rather than naming individual keys.

```bash
kubectl create secret generic app-secrets -n hepta \
  --dry-run=client -o yaml \
  --from-literal=DATABASE_URL="$(tofu -chdir=terraform/platform output -raw database_url)" \
  --from-literal=SUPABASE_URL="$SUPABASE_URL" \
  --from-literal=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=0 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/apps/heptapedal/app-secrets.sealed.yaml
```

`database_url` is already `app_user` over the VPC's private host with
`sslmode=require`; the database firewall trusts the cluster by UUID, so nothing
further is needed to reach it.

### The pull credential

Both images are private packages, so every pod spec needs a credential —
including the migration Job's, which is the one that fails confusingly
(see above). It is wave 0 for the same reason `app-secrets` is: PreSync pulls
an image before this Application's resources exist.

This is the second sealed copy of the GHCR token, the first being the one Argo
CD renders charts with ([platform/README](../platform/README.md#the-ghcr-registry-credential)).
Same classic PAT; a rotation touches both.

```bash
kubectl create secret docker-registry ghcr -n hepta \
  --dry-run=client -o yaml \
  --docker-server=ghcr.io \
  --docker-username=shogotsuneto \
  --docker-password="$GHCR_TOKEN" \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=0 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/apps/heptapedal/ghcr.sealed.yaml
```

Check that the type survived — a `docker-registry` Secret is only usable as one
if it keeps its type, and kubeseal carries that in `spec.template`:

```bash
grep 'type:' gitops/apps/heptapedal/ghcr.sealed.yaml   # kubernetes.io/dockerconfigjson
```

### agent-auth's Secret

With `oauth.enabled`, the chart also runs agent-auth — the OAuth authorization
server ChatGPT signs in through (heptapedal#84) — and its own migration Job,
another PreSync hook. That Job reads `agent-auth-secrets`, so the Secret is
wave 0 for exactly the reason `app-secrets` is.

The two services share no secret. agent-auth's holds only what is agent-auth's:

| Key | What | Its home |
|---|---|---|
| `AGENT_AUTH_DATABASE_URL` | `agent_auth_user` over the VPC's private host | Terraform state; the role's password can be reset in the console |
| `AGENT_AUTH_SIGNING_KEY` | P-256 private key, PKCS#8 PEM; signs every access token | none — see below |

The Supabase URL it also needs is read from `app-secrets` by the chart, so it is
not restated here.

Prerequisites, both from [`terraform/platform`](../../terraform/platform/README.md#agent-auths-database):
the database and role, with `sql/agent-auth.sql` run against them, and the
`agent-auth` DNS record.

```bash
kubectl create secret generic agent-auth-secrets -n hepta \
  --dry-run=client -o yaml \
  --from-literal=AGENT_AUTH_DATABASE_URL="$(tofu -chdir=terraform/platform output -raw agent_auth_database_url)" \
  --from-file=AGENT_AUTH_SIGNING_KEY=<(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256) \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=0 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/apps/heptapedal/agent-auth-secrets.sealed.yaml
```

The key is generated inside the pipeline, so it never touches the disk.
`genpkey` writes PKCS#8 (`-----BEGIN PRIVATE KEY-----`), which is the format
agent-auth expects; `ecparam -genkey` would write SEC1 and is not a substitute.

Check that both keys made it in:

```bash
grep -E '^\s+AGENT_AUTH_' gitops/apps/heptapedal/agent-auth-secrets.sealed.yaml
```

#### The signing key has no other copy, deliberately

That looks like the one thing [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md)
forbids: a sealed value that is its own only copy. It is not, because losing the
key is not a loss. Replacing it is the documented rotation:

- hepta refetches agent-auth's JWKS when it sees an unknown `kid`
- access tokens signed with the old key fail, and they live 10 minutes
- grants and refresh tokens are rows in `agent_auth`, not signatures, so they
  survive; each client's next refresh gets a token from the new key

So a rebuild that loses the sealing key costs connected apps at most ten
minutes, and nobody has to reconnect. Generating a fresh key is the recovery,
and a backup would be a second place for a signing key to leak from, without
saving anything.

**To rotate,** run the command above again, commit, and restart agent-auth once
it has synced. `envFrom` is read at start, so a Secret change alone does nothing:

```bash
kubectl -n hepta rollout restart deployment/agent-auth
```

#### Gateway access logs

agent-auth redirects to hepta's `/oauth/consent?authorization_id=…`, and that id
is a bearer secret until it is used or expires, which takes at most 10 minutes.
hepta and agent-auth never log query strings. The Gateway was checked on
2026-10-22:

- **Nothing persisted carries them.** The Gateway is Cilium's in-agent Envoy,
  with `debug=false` and no Hubble flow export. The agent's own log has no
  request lines, so what Alloy ships to Loki has no URLs.
- **Hubble's in-memory ring buffer may.** L7 flows can carry the URL, and they
  are readable through hubble-relay by whoever holds cluster-admin. That buffer
  is volatile, and the id is short-lived and single-use. Anyone who could read
  the buffer could also read the database, so it is accepted.

Re-check if Hubble flow export, or a Gateway access-log setting, is ever turned
on: `kubectl -n kube-system get cm cilium-config -o yaml | grep -iE 'export|access|debug'`.

#### After it syncs

```bash
# agent-auth's metadata, through the Gateway
curl -s https://agent-auth.heptapedal.com/.well-known/oauth-authorization-server

# /mcp now advertises it: a 401 that points at the protected-resource metadata,
# and that document naming agent-auth as its authorization server
curl -si -X POST https://heptapedal.com/mcp | grep -i www-authenticate
curl -s https://heptapedal.com/.well-known/oauth-protected-resource/mcp

# only the four public paths are routed; the consent API stays in-cluster
curl -s -o /dev/null -w '%{http_code}\n' https://agent-auth.heptapedal.com/grants   # 404
```

PAT clients are unaffected: `/mcp` tells the two apart by the `hep_pat_` prefix.

### On the database password specifically

It is generated by DigitalOcean and **is** in Terraform state — that is
unavoidable when Terraform creates the role, and the output is marked
`sensitive` so it does not reach a plan comment or a CI log.

That is consistent with [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md)
rather than an exception to it: the invariant is that a sealed value is never
its own only copy, and this one's home is the database itself, where it can be
reset and re-read. The Supabase values have their home in the Supabase console
for the same reason.
