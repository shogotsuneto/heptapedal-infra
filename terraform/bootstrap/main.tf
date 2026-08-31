# The bucket every other stack keeps its state in — and, after step 2 of
# README.md, this stack too.
#
# It is a Terraform resource rather than a hand-made bucket so that the settings
# protecting it are declared, reviewed and drift-detected. Made by hand they
# would be clicks nobody re-asserts, on the one resource whose loss costs the
# most: it holds platform/ and argocd/ state, and losing those orphans a live
# cluster, database and DNS zone that then have to be re-imported. See ADR 0003.
resource "digitalocean_spaces_bucket" "tfstate" {
  name   = var.bucket_name
  region = var.region
  acl    = "private"

  # Recovers a state object that was corrupted or overwritten. It does NOT
  # protect the bucket itself — that is what the two settings below are for.
  versioning {
    enabled = true
  }

  # The guard that actually works: S3 and Spaces refuse to delete a non-empty
  # bucket, so while any stack's state is in here, `destroy` cannot take it.
  # Never set this to true.
  force_destroy = false

  # Belt to that braces. Note this is the Terraform meta-argument, unrelated to
  # the `lifecycle_rule` below.
  lifecycle {
    prevent_destroy = true
  }

  # State objects are small, but every write leaves a version behind forever.
  # Keep three months of rollback and let the rest expire.
  lifecycle_rule {
    id      = "expire-noncurrent-state"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }
}
