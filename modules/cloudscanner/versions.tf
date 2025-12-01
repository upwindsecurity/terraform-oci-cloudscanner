terraform {
  required_version = ">= 1.2"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 7.27.0, < 8.0.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}
