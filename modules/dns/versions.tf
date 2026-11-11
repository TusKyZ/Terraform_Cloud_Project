terraform {
  # Minimum versions only, as HashiCorp recommends for child modules: the root
  # module sets the allowed range and the lock file pins the exact version.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
