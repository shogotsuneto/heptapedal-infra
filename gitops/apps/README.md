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

## orderassist

A voice ordering assistant: its core and its voice agent, released together as
one chart at `orderassist.heptapedal.com`. Its print worker runs at the
restaurant and comes in over `wss://nats.heptapedal.com`.

| Wave | What |
|---|---|
| -1 | `orderassist` namespace |
| 0 | five Secrets, and the `ghcr` pull credential |
| 1 | `orderassist` |

The chart creates none of what it depends on. From this repository: the
Secrets below, the `ORDERASSIST` account in
[`../platform/nats.yaml`](../platform/nats.yaml), and the database in
[`terraform/platform`](../../terraform/platform/README.md#orderassists-database).
It has no migration Job — the core migrates its database itself when it
starts — so the waves only keep a stale seal from letting it deploy.

### Sealing its Secrets

Before starting: the database applied and `sql/orderassist.sql` run, and the
chart version `app.yaml` pins published. Run everything from the repository
root, with `direnv allow` done, so `kubeseal` reaches this cluster and `tofu`
reads the state.

The values are generated or typed inside the pipelines and never touch the
disk. `read -rs` keeps the typed ones out of the shell's history. One helper
seals what `kubectl create` prints, in the shape every sealed file here has:

```bash
seal() {  # seal NAME < Secret: writes gitops/apps/orderassist/NAME.sealed.yaml
  kubeseal --format yaml \
    | kubectl annotate --local -f - -o yaml \
        argocd.argoproj.io/sync-wave=0 \
        argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
    > "gitops/apps/orderassist/$1.sealed.yaml"
}
```

**1. The core's and the voice agent's NATS users.** As
[platform/README](../platform/README.md#adding-an-application) does it, one
user per service: the seed is sealed, and the public key replaces its
placeholder in `nats.yaml`.

```bash
for service in core voice-agent; do
  keys=$(nats auth nkey gen user --public)
  kubectl create secret generic "orderassist-nats-$service" -n orderassist \
    --dry-run=client -o yaml \
    --from-literal=nats.nk="$(sed -n 1p <<<"$keys")" \
    | seal "orderassist-nats-$service"
  placeholder="REPLACE_WITH_$(tr a-z- A-Z_ <<<"$service")_PUBLIC_KEY"
  perl -pi -e "s/$placeholder/$(sed -n 2p <<<"$keys")/" gitops/platform/nats.yaml
done
```

**2. The print worker's NATS user.** A device, as in
[platform/README](../platform/README.md#adding-a-device): its seed is created
where the worker will run and stays there, so it is never sealed. Until it runs
at the restaurant, that is this laptop:

```bash
mkdir -p ~/.config/nats && chmod 700 ~/.config/nats
(umask 077; nats auth nkey gen user --output ~/.config/nats/orderassist-print-worker.nk)
perl -pi -e "s/REPLACE_WITH_PRINT_WORKER_PUBLIC_KEY/$(nats auth nkey show ~/.config/nats/orderassist-print-worker.nk)/" \
  gitops/platform/nats.yaml
```

**3. The core's database URL and staff password.** The password is the one
staff sign in to `/staff` with; changing it later signs every member of staff
out.

```bash
read -rs -p 'Staff password: ' STAFF_PASSWORD; echo
kubectl create secret generic orderassist-core -n orderassist \
  --dry-run=client -o yaml \
  --from-literal=DATABASE_URL="$(tofu -chdir=terraform/platform output -raw orderassist_database_url)" \
  --from-literal=STAFF_PASSWORD="$STAFF_PASSWORD" \
  | seal orderassist-core
unset STAFF_PASSWORD
```

**4. The voice agent's OpenAI API key.**

```bash
read -rs -p 'OpenAI API key: ' OPENAI_API_KEY; echo
kubectl create secret generic orderassist-voice-agent -n orderassist \
  --dry-run=client -o yaml \
  --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
  | seal orderassist-voice-agent
unset OPENAI_API_KEY
```

**5. The conversation signing key pair.** Ed25519: the core signs each
conversation's token with the private key, and the voice agent, which gets only
the public one, verifies it. Both come from one key generated in the pipeline:

```bash
private=$(openssl genpkey -algorithm ed25519)
kubectl create secret generic orderassist-conversation-key -n orderassist \
  --dry-run=client -o yaml \
  --from-literal=private.pem="$private" \
  --from-literal=public.pem="$(openssl pkey -pubout <<<"$private")" \
  | seal orderassist-conversation-key
unset private
```

**6. The pull credential**, the same classic PAT as heptapedal's
([the pull credential](#the-pull-credential)): a third copy, so a rotation
touches all three.

```bash
read -rs -p 'GHCR token: ' GHCR_TOKEN; echo
kubectl create secret docker-registry ghcr -n orderassist \
  --dry-run=client -o yaml \
  --docker-server=ghcr.io \
  --docker-username=shogotsuneto \
  --docker-password="$GHCR_TOKEN" \
  | seal ghcr
unset GHCR_TOKEN
```

**Check, then commit** the six files and `nats.yaml`:

```bash
grep -c REPLACE_WITH gitops/platform/nats.yaml        # 0
grep -E '^    [A-Za-z._]+: Ag' gitops/apps/orderassist/*.sealed.yaml | cut -d: -f1,2
grep 'type:' gitops/apps/orderassist/ghcr.sealed.yaml # kubernetes.io/dockerconfigjson
```

The second command should list, by file: `DATABASE_URL` and `STAFF_PASSWORD`;
`OPENAI_API_KEY`; `private.pem` and `public.pem`; `nats.nk` twice; and
`.dockerconfigjson`.

### Where its values come from

None of them is a sealed value's only copy that matters
([ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md)): each is in the
service that owns it, or is replaced by generating it again.

| Value | Its home |
|---|---|
| `DATABASE_URL` | Terraform state, `orderassist_database_url`; the role's password can be reset in the console |
| `STAFF_PASSWORD` | the operator's password manager; a new one only signs staff out |
| `OPENAI_API_KEY` | the OpenAI platform, where a new key is issued |
| the conversation key pair | none: regenerating it ends the conversations under way, whose tokens it signed, and nothing else |
| the NATS seeds | none: a new seed and its public key in `nats.yaml`, as for heptapedal's |
| the print worker's seed | the device it runs on, never sealed |
| `ghcr` | the classic PAT, as heptapedal's |

### After it syncs

```bash
kubectl -n orderassist get pods                   # core and voice-agent Running, Ready
curl -s https://orderassist.heptapedal.com/healthz  # {"nats":"ok","postgres":"ok"}
curl -si https://orderassist.heptapedal.com/ws | head -1   # 403: no conversation token
kubectl -n orderassist get httproute orderassist -o jsonpath='{.status.parents[0].conditions[*].type}'
```

A core that cannot reach NATS or Postgres keeps retrying and answers
`/healthz` with 503, so the first thing to read is its log:
`kubectl -n orderassist logs deploy/orderassist-core`.
