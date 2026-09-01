# The zone. Delegation itself is a manual step at Namecheap — see README.md.
#
# Order matters: this must exist before the nameservers are switched, or the
# domain resolves to nothing while DigitalOcean has no zone to answer from.
#
# No `ip_address` argument: it would create an apex A record, and there is
# nothing to point one at until the Gateway's Load Balancer exists (#20).
resource "digitalocean_domain" "heptapedal" {
  name = var.domain
}

# Restrict who may issue certificates for this domain to Let's Encrypt, which is
# the only issuer cert-manager will use (ADR 0009). Cheap, and it means a
# mis-issuance elsewhere cannot quietly produce a valid certificate for
# heptapedal.com.
#
# `issue` alone would already cover wildcards, but stating `issuewild` makes the
# wildcard in ADR 0009 explicit rather than inherited.
resource "digitalocean_record" "caa_issue" {
  domain = digitalocean_domain.heptapedal.id
  type   = "CAA"
  name   = "@"
  flags  = 0
  tag    = "issue"
  value  = "letsencrypt.org."
}

resource "digitalocean_record" "caa_issuewild" {
  domain = digitalocean_domain.heptapedal.id
  type   = "CAA"
  name   = "@"
  flags  = 0
  tag    = "issuewild"
  value  = "letsencrypt.org."
}
