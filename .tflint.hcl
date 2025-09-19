# TFLint configuration for Algalon Terraform
config {
  format = "compact"
  plugin_dir = "~/.tflint.d/plugins"

  call_module_type = "all"
  force = false
  disabled_by_default = false
}

# Enable specific rule sets
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.25.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Custom rules for Algalon
rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_standard_module_structure" {
  enabled = true
}

# Google Cloud specific rules
rule "google_compute_instance_serial_port" {
  enabled = true
}

rule "google_compute_firewall_rule_allow_all" {
  enabled = true
}

rule "google_project_iam_member_role_too_broad" {
  enabled = true
}

rule "google_sql_database_instance_backup_configuration" {
  enabled = true
}

rule "google_storage_bucket_uniform_bucket_level_access" {
  enabled = true
}

# Disable rules that are too strict for our use case
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}