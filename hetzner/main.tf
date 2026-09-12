# Hetzner leg resources.
#
# The legacy k3s/NixOS nodes (ts-hz-ctl CX23, ts-hz-db CX33) and the `timestone`
# firewall are retired: the Talos backend in talos.tf is now the sole compute.
# The legacy operator SSH key (timestone_ops) is intentionally left installed in
# the project for manual access and is no longer Terraform-managed.

terraform {
  required_version = ">= 1.6"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-beta.0"
    }
    imager = {
      source  = "hcloud-talos/imager"
      version = "~> 1.0"
    }
  }
  # Remote state backend TBD (home SeaweedFS S3). Local-only until then.
}

provider "hcloud" {
  # token is read from the HCLOUD_TOKEN environment variable (migration: the
  # previously-required variable/provider argument is removed).
}

provider "imager" {}
