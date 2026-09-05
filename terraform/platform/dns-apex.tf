# The apex A record: heptapedal.com -> the Gateway's Load Balancer.
#
# The IP is a variable rather than something looked up, and that is a smaller
# concession than it first appears. Writing this record does not consult what
# lives at the address — DigitalOcean stores the value it is given — so the
# record is data, not a dependency on the cluster. What it *is* is a value whose
# origin sits downstream, in GitOps: the Load Balancer, and therefore its
# address, are created when Argo CD reconciles the Gateway.
#
# So there is no ordering problem to solve, only a fact to keep true — and
# nothing here enforces it. Terraform compares configuration against state,
# never against reality, so a stale `apex_ip` produces no diff at all: the
# record matches what was asked for, and the plan is clean while the site is
# unreachable.
#
# That gap is covered by external monitoring rather than here (#23). A Terraform
# `check` block did live in this file and could read the balancer's real
# address, but it cost 69% of every plan's output to a re-read it must perform
# on each run, plus a `load_balancer:read` scope existing only for it — to
# detect, only at the moment someone plans, what a synthetic probe detects
# continuously and from outside.
#
# What that trade gives up is the precise message. A probe says the site is
# down; it does not say which value is stale. So: **if heptapedal.com breaks,
# check `apex_ip` against the live address before looking further.**
#
#   kubectl get gateway heptapedal -n gateway \
#     -o jsonpath='{.status.addresses[0].value}'
resource "digitalocean_record" "apex" {
  count = var.apex_record ? 1 : 0

  domain = digitalocean_domain.heptapedal.id
  type   = "A"
  name   = "@"
  value  = var.apex_ip

  # Deliberately short. This record is expected to change — a rebuilt cluster
  # gets a new Load Balancer and a new address, and there is no way to pin one
  # (reserved IPs cannot attach to DigitalOcean Load Balancers, and the
  # `do-loadbalancer-ip` annotation takes a BYOIP prefix, which is a different
  # product). A low TTL means the switch costs minutes rather than half an hour,
  # without having to remember to lower it beforehand.
  ttl = var.apex_ttl
}
