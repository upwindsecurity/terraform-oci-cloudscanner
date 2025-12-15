variable "oracle_region" {
  type        = string
  description = "The Oracle region of the deployed resources."

  validation {
    condition     = length(trimspace(var.oracle_region)) > 0
    error_message = "The variable 'oracle_region' must not be empty or contain only whitespace."
  }
}

variable "auth_token" {
  type        = string
  description = "Oracle Auth Token used for authenticating against the Oracle Container Registry for image scans"
}

variable "availability_zones" {
  type        = list(any)
  description = "The zones within the region that will be used for zone based resources."
  default     = ["oHrk:US-ASHBURN-AD-1", "oHrk:US-ASHBURN-AD-2", "oHrk:US-ASHBURN-AD-3"]
}

variable "compartment_id" {
  type        = string
  description = "The root compartment where the cloudscanner needs to be deployed"

  validation {
    condition     = length(trimspace(var.compartment_id)) > 0
    error_message = "The variable 'compartment_id' must not be empty or contain only whitespace."
  }
}

variable "tenancy_id" {
  type        = string
  description = "The OCI tenancy OCID for querying platform images"
  default     = ""

  validation {
    condition     = var.tenancy_id == "" || can(regex("^ocid1\\.tenancy\\..*", var.tenancy_id))
    error_message = "The tenancy_id must be a valid tenancy OCID starting with 'ocid1.tenancy.'"
  }
}

variable "object_namespace" {
  type        = string
  description = "The object namespace associated with the tenancy"
}

variable "account_user" {
  type        = string
  description = "The Service Account User required for image scans"
}

variable "scanner_id" {
  type        = string
  description = "The Upwind Scanner ID."

  validation {
    condition     = length(trimspace(var.scanner_id)) > 0
    error_message = "The variable 'scanner_id' must not be empty or contain only whitespace."
  }
}

variable "upwind_region" {
  type        = string
  description = "Which Upwind region to communicate with. 'us' or 'eu'"
  default     = "us"

  validation {
    condition     = var.upwind_region == "us" || var.upwind_region == "eu" || var.upwind_region == "me" || var.upwind_region == "pdc"
    error_message = "upwind_region must be either 'us' or 'eu' or 'me' or 'pdc'."
  }
}

variable "target_size" {
  type        = number
  description = "Target size of the instance pool to be ran when starting the deployment"
  default     = 10
}

variable "public_uri_domain" {
  type        = string
  description = "The public URI domain."
  default     = "upwind.io"
}

variable "extra_tags" {
  description = "Map of required tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "shape" {
  description = "Shape of the Cloudscanner worker VM"
  type        = string
  default     = "VM.Standard.E5.Flex"
}

variable "boot_volume_size" {
  description = "Boot size for VM disk space"
  type        = number
  default     = 50
}

resource "random_string" "scanner_suffix" {
  length  = 6
  upper   = false
  special = false
}

variable "ocpus" {
  description = "Number of OCPUs for flexible shapes"
  type        = number
  default     = 4

  validation {
    condition     = var.ocpus >= 1
    error_message = "ocpus must be >= 1."
  }
}

variable "memory_in_gbs" {
  description = "Memory in GB for flexible shapes"
  type        = number
  default     = 4

  validation {
    condition     = var.memory_in_gbs >= var.ocpus && (var.memory_in_gbs / var.ocpus) >= 1 && (var.memory_in_gbs / var.ocpus) <= 64
    error_message = "memory_in_gbs must be >= ocpus and the memory_in_gbs/ocpus ratio must be between 1 and 64."
  }
}

locals {
  default_freeform_tags = {
    UpwindComponent = "CloudScanner"
    UpwindScannerId = var.scanner_id
  }

  is_flexible_shape = contains(split(".", lower(var.shape)), "flex")

  freeform_tags = merge(local.default_freeform_tags, var.extra_tags)

  common_scanner_name = "${var.scanner_id}_${random_string.scanner_suffix.result}"
}
