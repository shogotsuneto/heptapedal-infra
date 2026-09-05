# The apex A record: heptapedal.com -> the Gateway's Load Balancer.
#
# The IP is a variable rather than something looked up, and that is a smaller
# concession than it first appears. Writing this record does not consult what
# lives at the address — DigitalOcean stores the value it is given — so the
# record is data, not a dependency on the cluster. What it *is* is a value whose
# origin sits downstream, in GitOps: the Load Balancer, and therefore its
# address, are created when Argo CD reconciles the Gateway.
#
# So there is no ordering problem to solve, only a fact to keep true. The check
# block below is what keeps it honest.
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

# Terraform compares configuration against state, never against reality, so a
# stale `apex_ip` produces no diff: the record matches what was asked for, and
# the plan is clean while the site is unreachable. Nothing here would notice.
#
# A check block notices, and does so without turning the record into a
# dependency — scoped data source failures are masked as warnings, and failed
# assertions are warnings too, so a cluster that has no Load Balancer yet still
# plans and applies cleanly.
#
# Requires `load_balancer:read` on the DigitalOcean token. Without that scope
# the data source 403s and every plan carries a warning, which is worse than no
# check at all: either grant the scope or delete this block.
check "apex_matches_the_load_balancer" {
  data "digitalocean_loadbalancer" "gateway" {
    # Fixed by the Gateway's do-loadbalancer-name annotation, so this survives
    # the Load Balancer being recreated.
    name = "heptapedal"
  }

  assert {
    condition = !var.apex_record || data.digitalocean_loadbalancer.gateway.ip == var.apex_ip
    error_message = format(
      "apex_ip is %s but the load balancer is at %s — heptapedal.com points nowhere. Update apex_ip.",
      var.apex_ip,
      data.digitalocean_loadbalancer.gateway.ip,
    )
  }
}
