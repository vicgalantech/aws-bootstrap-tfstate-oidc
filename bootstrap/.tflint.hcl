plugin "aws" {
  enabled = true
  version = "0.36.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enforce naming conventions
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  locals {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }
}

# Require all variables to have a description
rule "terraform_documented_variables" {
  enabled = true
}

# Require all outputs to have a description
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn on deprecated interpolation syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Warn on unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Require type constraints on variables
rule "terraform_typed_variables" {
  enabled = true
}
