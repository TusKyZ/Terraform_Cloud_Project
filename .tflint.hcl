# TFLint settings for the whole repository. From the repository root:
#   tflint --init
#   tflint --recursive --config "$(pwd)/.tflint.hcl"
# --recursive looks for a config file in each module folder, so --config
# points every folder at this one.

plugin "terraform" {
  enabled = true
  preset  = "all"
}

# AWS rules, such as invalid instance types. deep_check stays off, so the
# linter never calls AWS.
plugin "aws" {
  enabled    = true
  version    = "0.49.0"
  source     = "github.com/terraform-linters/tflint-ruleset-aws"
  deep_check = false
}
