# Enabled at step 2 of README.md, once the bucket exists. The stack self-hosts:
# its state lives in the bucket it created, so no state file is ever committed
# (ADR 0012).
#
# A backend block cannot reference variables, so these are literals. Keep them
# in step with variables.tf.
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    bucket = "heptapedal-tfstate"
    key    = "bootstrap/terraform.tfstate"

    # S3-native locking: a .tflock object written with a conditional put. No
    # DynamoDB equivalent required. See ADR 0003.
    use_lockfile = true

    # Spaces is S3-compatible but is not AWS. `region` is a required
    # placeholder, and these checks either do not apply or are not implemented.
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
