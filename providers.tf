terraform {
  # first in terminal run `terraform login`
  cloud {
    organization = "jvinnie-test"
    #hostname = "app.terraform.io" # Optional; defaults to app.terraform.io
    workspaces {
      name = "tf-aws-vpc"
    }
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.6.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

