terraform {
  # Minimum versions only, as HashiCorp recommends for child modules: the root
  # module sets the allowed range and the lock file pins the exact version.
  # The WordPress keys need write-only arguments (Terraform 1.11) and the
  # ephemeral random_password (random 3.7).
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
