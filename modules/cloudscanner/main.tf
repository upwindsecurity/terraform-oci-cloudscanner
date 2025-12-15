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



