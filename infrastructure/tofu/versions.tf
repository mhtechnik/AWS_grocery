# OpenTofu Quick Commands (aus diesem Ordner):
# tofu init
# tofu fmt -recursive
# tofu validate
# tofu plan -var-file=dev.tfvars -out=plan.tfplan
# tofu apply plan.tfplan
# tofu destroy -var-file=dev.tfvars

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

