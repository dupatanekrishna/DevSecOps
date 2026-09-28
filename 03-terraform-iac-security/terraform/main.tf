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

# Final remediated state.
# The experiment first used 0.0.0.0/0 and Checkov CKV_AWS_24 failed.
resource "aws_security_group" "restricted_ssh" {
  name        = "checkov-security-lab"
  description = "Restricted SSH rule for Checkov security testing"

  ingress {
    description = "SSH restricted to trusted/private network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "10.0.0.0/8"
    ]
  }
}
