terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # or search for the latest version from https://registry.terraform.io/providers/hashicorp/aws/latest/docs
    }
  }
}

provider "aws" {
  profile = "default" # put the profile name of account a from your aws
  region = "ap-south-1" # put the region code where you are working
}

provider "aws" {
  alias  = "account_personal"
  profile = "avinash.s" # put the profile name of account b from your aws credentials file
  region = "ap-south-1" # put the region code where you are working
}