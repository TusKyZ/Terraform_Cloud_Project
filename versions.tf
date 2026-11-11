terraform {
  # 1.11 or newer: S3-native state locking (use_lockfile in backend.tf) is
  # generally available from 1.11.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 3.7 or newer: the compute module uses the ephemeral random_password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
