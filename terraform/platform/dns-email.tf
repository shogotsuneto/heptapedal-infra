# Email authentication for Resend, which fronts Amazon SES and which Supabase
# uses as custom SMTP. These carry sign-up confirmation and password-reset
# links — without them the application's only sign-up path stops working, since
# it is email-first (see the application repo's README).
#
# Replicated verbatim from the Namecheap zone, TTLs included. Nothing here is
# improved or tidied on the way across: fidelity now, opinions later.
#
# They must exist here BEFORE the nameservers are switched. See README.md.

# Bounce and complaint handling for the custom MAIL FROM domain. SPF is checked
# against the return-path, which is send.heptapedal.com rather than the apex —
# which is why the apex has no SPF record and does not need one.
resource "digitalocean_record" "send_spf" {
  domain = digitalocean_domain.heptapedal.id
  type   = "TXT"
  name   = "send"
  value  = "v=spf1 include:amazonses.com ~all"
  ttl    = 1800
}

resource "digitalocean_record" "send_mx" {
  domain   = digitalocean_domain.heptapedal.id
  type     = "MX"
  name     = "send"
  value    = "feedback-smtp.us-east-1.amazonses.com."
  priority = 10
  ttl      = 1800
}

# DKIM public key. Public by definition — a DKIM record is published so that
# receivers can verify signatures — so committing it discloses nothing.
resource "digitalocean_record" "resend_dkim" {
  domain = digitalocean_domain.heptapedal.id
  type   = "TXT"
  name   = "resend._domainkey"
  value  = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDcDrMdlWmsHNXvN0bTHEk6iCoS9+ux6SxQf/lZg5o6lFtdpDQ8yu5utgnXuwYz5yWyi6rjcakSdv+e2Zrv1rdxURzGwty88Oh3IsdxT64dBzEwhTXRM7vEDcpZw7ZRTnQDrenufkuFFKhdxvlXyN8Bc7ToWFqNtcvoNf4P23vIWwIDAQAB"
  ttl    = 1800
}

resource "digitalocean_record" "dmarc" {
  domain = digitalocean_domain.heptapedal.id
  type   = "TXT"
  name   = "_dmarc"
  value  = "v=DMARC1; p=none;"
  ttl    = 1800
}
