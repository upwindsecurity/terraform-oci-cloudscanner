resource "oci_core_instance_pool" "cloudscanner_instance_pool" {
  compartment_id            = var.compartment_id
  display_name              = "upwind-cs-asg-${var.scanner_id}"
  instance_configuration_id = oci_core_instance_configuration.cloudscanner_instance_configuration.id
  size                      = var.target_size

  dynamic "placement_configurations" {
    for_each = toset(var.availability_zones)
    content {
      availability_domain = placement_configurations.value
      primary_vnic_subnets {
        subnet_id = oci_core_subnet.cloudscanner_regional_subnet.id
      }
    }
  }

  freeform_tags = merge(local.freeform_tags, {
    Name = "upwind-cs-asg-${var.scanner_id}"
  })

  lifecycle {
    replace_triggered_by = [null_resource.always_run]
  }
}

resource "null_resource" "always_run" {
  triggers = {
    always_run = var.public_uri_domain
  }
}

data "oci_core_images" "cloudscanner" {
  # Platform images are available at the tenancy level, so query from tenancy if provided
  # Otherwise fall back to the compartment_id
  compartment_id           = var.tenancy_id != "" ? var.tenancy_id : var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  # For flexible shapes, don't filter by shape as it may exclude compatible images
  # Most platform images published after flexible shapes were released are compatible
  # OCI will validate image compatibility at instance launch time
  shape      = local.is_flexible_shape ? null : var.shape
  sort_by    = "TIMECREATED"
  sort_order = "DESC"

  filter {
    name   = "state"
    values = ["AVAILABLE"]
  }
}

# --- Lookup Upwind OAuth credentials from an existing OCI Vault (made during onboarding) ---
# This stack derives the vault display name from the same resource suffix used by the vault stack.
# It then discovers the secret OCIDs by secret_name and fetches the CURRENT secret bundle values.

locals {
  # This must match the suffix used when the vault stack created the vault and secrets.
  resource_suffix_hyphen = var.resource
  upwind_vault_display_name = format("upwind-vault-%s", local.resource_suffix_hyphen)

  upwind_client_id_secret_name     = format("upwind-client-id-%s", local.resource_suffix_hyphen)
  upwind_client_secret_secret_name = format("upwind-client-secret-%s", local.resource_suffix_hyphen)
}

# Find the vault by display name in this compartment
data "oci_kms_vaults" "upwind" {
  compartment_id = var.compartment_id

  filter {
    name   = "display_name"
    values = [local.upwind_vault_display_name]
  }
}

locals {
  upwind_vault_id = data.oci_kms_vaults.upwind.vaults[0].id
}

# List all secrets in the vault and pick the two we need by secret_name
data "oci_vault_secrets" "upwind" {
  compartment_id = var.compartment_id
  vault_id       = local.upwind_vault_id
}

locals {
  upwind_client_id_secret_ocid = one([
    for s in data.oci_vault_secrets.upwind.secrets :
    s.id if s.secret_name == local.upwind_client_id_secret_name
  ])

  upwind_client_secret_secret_ocid = one([
    for s in data.oci_vault_secrets.upwind.secrets :
    s.id if s.secret_name == local.upwind_client_secret_secret_name
  ])
}

# Fetch values into locals.
data "oci_secrets_secretbundle" "upwind_client_id" {
  secret_id = local.upwind_client_id_secret_ocid
  stage     = "CURRENT"
}

data "oci_secrets_secretbundle" "upwind_client_secret" {
  secret_id = local.upwind_client_secret_secret_ocid
  stage     = "CURRENT"
}

locals {
  upwind_client_id     = base64decode(data.oci_secrets_secretbundle.upwind_client_id.secret_bundle_content[0].content)
  upwind_client_secret = base64decode(data.oci_secrets_secretbundle.upwind_client_secret.secret_bundle_content[0].content)
}

locals {
  # Ensure we have at least one image available
  # Handle null case when no images are found in the region
  images_list = try(data.oci_core_images.cloudscanner.images, [])
  image_id    = length(local.images_list) > 0 ? local.images_list[0].id : null
}

resource "oci_core_instance_configuration" "cloudscanner_instance_configuration" {
  compartment_id = var.compartment_id
  display_name   = "${var.scanner_id}-cloudscanner-instance-configuration"

  depends_on = [
    oci_core_subnet.cloudscanner_regional_subnet,
  ]

  instance_details {
    instance_type = "compute"
    launch_details {
      compartment_id = var.compartment_id

      shape         = var.shape
      freeform_tags = local.freeform_tags
      dynamic "shape_config" {
        for_each = local.is_flexible_shape ? [1] : []
        content {
          ocpus         = var.ocpus
          memory_in_gbs = var.memory_in_gbs
        }
      }

      source_details {
        source_type             = "image"
        image_id                = local.image_id
        boot_volume_size_in_gbs = var.boot_volume_size
      }
      create_vnic_details {
        subnet_id        = oci_core_subnet.cloudscanner_regional_subnet.id
        assign_public_ip = false
      }

      metadata = {
        # Startup script equivalent to GCP metadata_startup_script
        user_data = base64encode(<<-EOF
          #!/bin/bash
          echo "Getting upwind credentials..."
          export ORACLE_REGION=${var.oracle_region}
          export UPWIND_CLOUDSCANNER_ID=${var.scanner_id}
          export DOCKER_USER=${var.account_user}
          export DOCKER_PASSWORD=${var.auth_token}
          export TENANCY_NAMESPACE=${var.object_namespace}
          export UPWIND_CLIENT_ID='${local.upwind_client_id}'
          export UPWIND_CLIENT_SECRET='${local.upwind_client_secret}'

          # OCI authentication for instance principal
          export OCI_CLI_AUTH=instance_principal
          export OCI_CLI_REGION=${var.oracle_region}

          echo "Downloading CloudScanner..."
          curl -L https://get.${var.public_uri_domain}/cloudscanner.sh -O
          chmod +x cloudscanner.sh
          UPWIND_INFRA_REGION=${var.upwind_region} UPWIND_IO=${var.public_uri_domain} bash ./cloudscanner.sh
          echo "CloudScanner install finished for ${var.scanner_id}..."
        EOF
        )
      }
    }
  }

  lifecycle {
    replace_triggered_by  = [null_resource.always_run]
    create_before_destroy = true
    precondition {
      condition     = local.image_id != null
      error_message = "No matching Ubuntu 22.04 image found for shape ${var.shape} in region ${var.oracle_region}."
    }
  }
}
