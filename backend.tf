# Remote state is switched off on purpose. The plan profile is read-only and
# cannot write the S3 lock file, so state stays local. To switch: create the
# bucket, uncomment the block below, then run `terraform init -migrate-state`.
#
# terraform {
#   backend "s3" {
#     bucket       = "<state-bucket-name>"
#     key          = "web-school/prod/terraform.tfstate"
#     region       = "ap-southeast-3"
#     use_lockfile = true # S3-native lock file, no DynamoDB table needed
#     encrypt      = true
#   }
# }
