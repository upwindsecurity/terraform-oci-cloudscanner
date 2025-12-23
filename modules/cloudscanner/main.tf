resource "oci_core_instance_pool" "cloudscanner_instance_pool" {
  compartment_id            = var.compartment_id
  display_name              = "upwind-cs-asg-${var.scanner_id}"
  instance_configuration_id = oci_core_instance_configuration.cloudscanner_instance_configuration.id
  size                      = var.target_size

  dynamic "placement_configurations" {
    for_each = toset(local.availability_zones)
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

# Get availability domains for the region
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_id != "" ? var.tenancy_id : var.compartment_id
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

# Query shapes compatible with the selected image
data "oci_core_shapes" "compatible_shapes" {
  count          = local.image_id != null ? 1 : 0
  compartment_id = var.compartment_id
  image_id       = local.image_id
}

locals {
  # Ensure we have at least one image available
  # Handle null case when no images are found in the region
  # Use coalesce to default to empty list if images is null
  images_list = coalesce(data.oci_core_images.cloudscanner.images, [])
  image_id    = length(local.images_list) > 0 ? local.images_list[0].id : null

  # Get availability domain names from the data source
  availability_domain_names = [
    for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name
  ]

  # Use provided availability_zones if specified, otherwise use all availability domains from the region
  # This ensures region-agnostic deployment - availability domains are automatically discovered
  availability_zones = length(var.availability_zones) > 0 ? (
    var.availability_zones
    ) : (
    local.availability_domain_names
  )

  # Get list of compatible shapes for the image
  compatible_shapes_list = local.image_id != null && length(data.oci_core_shapes.compatible_shapes) > 0 ? (
    coalesce(data.oci_core_shapes.compatible_shapes[0].shapes, [])
  ) : []

  # Extract shape names from compatible shapes
  compatible_shape_names = [
    for shape in local.compatible_shapes_list : shape.name
  ]

  # Preferred flexible shapes in order of preference (most powerful first)
  preferred_flexible_shapes = [
    "VM.Standard.E5.Flex",
    "VM.Standard.E4.Flex",
    "VM.Standard.E3.Flex",
    "VM.Standard.E2.Flex",
    "VM.Standard.A1.Flex"
  ]

  # Select a compatible shape:
  # 1. If the provided shape is compatible, use it
  # 2. For flexible shapes, if provided shape is not compatible, try to find a compatible flexible shape
  # 3. For non-flexible shapes, use provided shape (will fail at apply if incompatible with clearer error)
  selected_shape = local.is_flexible_shape ? (
    # For flexible shapes, check if provided shape is compatible
    contains(local.compatible_shape_names, var.shape) ? var.shape : (
      # Try to find a compatible flexible shape from preferred list
      length([
        for preferred in local.preferred_flexible_shapes :
        preferred if contains(local.compatible_shape_names, preferred)
        ]) > 0 ? [
        for preferred in local.preferred_flexible_shapes :
        preferred if contains(local.compatible_shape_names, preferred)
        ][0] : (
        # If no preferred shape is compatible, try any compatible flexible shape
        length([
          for shape_name in local.compatible_shape_names :
          shape_name if contains(split(".", lower(shape_name)), "flex")
          ]) > 0 ? [
          for shape_name in local.compatible_shape_names :
          shape_name if contains(split(".", lower(shape_name)), "flex")
        ][0] : var.shape
      )
    )
    ) : (
    # For non-flexible shapes, use provided shape
    var.shape
  )
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

      shape         = local.selected_shape
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
    precondition {
      condition     = local.image_id == null || length(local.compatible_shapes_list) > 0
      error_message = "No compatible shapes found for image ${local.image_id} in region ${var.oracle_region}. Requested shape: ${var.shape}. Available compatible shapes: ${join(", ", local.compatible_shape_names)}"
    }
    precondition {
      condition     = local.image_id == null || contains(local.compatible_shape_names, local.selected_shape)
      error_message = "Shape ${var.shape} is not compatible with the selected image in region ${var.oracle_region}. Selected compatible shape: ${local.selected_shape}. Available compatible shapes: ${join(", ", local.compatible_shape_names)}"
    }
  }
}



