// =====================================================================
// Chapter 10, Section 2.4: Storing state in a remote backend
// =====================================================================
// Local terraform.tfstate is invisible to CI and unsafe under concurrent
// applies. HCP Terraform (free tier) provides remote state and locking.
// After uncommenting: terraform login once, then terraform init.
//
// Left commented so a local terraform validate / plan walkthrough works
// without an HCP account. Uncomment before wiring the CI pipeline that
// reads TF_API_TOKEN.
// =====================================================================

# terraform {
#   cloud {
#     organization = "techflow-data"
#
#     workspaces {
#       name = "snowflake-infra"
#     }
#   }
# }
