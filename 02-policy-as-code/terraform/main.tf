terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Intentionally insecure for the policy-gate experiment.
# DO NOT apply this configuration.
resource "aws_security_group" "bad_ssh" {
  name        = "opa-policy-lab"
  description = "OPA Policy as Code lab"

  ingress {
    description = "Deliberately insecure SSH rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}
