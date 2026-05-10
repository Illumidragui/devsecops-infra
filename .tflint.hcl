# tflint configuration — base rules only.
# To add AWS-specific rules (recommended), uncomment the plugin block and run
# `tflint --init` locally. The CI pipeline will download the plugin automatically.
#
# plugin "aws" {
#   enabled = true
#   version = "0.36.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible"
}
