# Tests for bring-your-own-network mode (var.create_network / vcn_id / subnet_id).
# Providers are mocked and every run is a plan, so no OCI credentials are needed.

mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [{ name = "AD-1" }]
    }
  }
  mock_data "oci_core_images" {
    defaults = {
      images = [{ id = "ocid1.image.oc1..test" }]
    }
  }
  mock_data "oci_core_shapes" {
    defaults = {
      shapes = [{ name = "VM.Standard.E5.Flex" }]
    }
  }
  # The provided-subnet lookup used to validate BYO network input. Its vcn_id is
  # fixed here; tests set var.vcn_id to match (or mismatch) this value.
  mock_data "oci_core_subnet" {
    defaults = {
      vcn_id         = "ocid1.vcn.oc1..mockvcn"
      compartment_id = "ocid1.compartment.oc1..test"
    }
  }
}
mock_provider "null" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "archive" {}

variables {
  oracle_region                = "us-ashburn-1"
  auth_token                   = "token"
  compartment_id               = "ocid1.compartment.oc1..test"
  upwind_scanner_client_id     = "client"
  upwind_scanner_client_secret = "secret"
  object_namespace             = "namespace"
  account_user                 = "user"
  scanner_id                   = "ucsc-test"
  upwind_org_id                = "org_test"
}

# --- Managed mode (default, create_network = true): module creates its network ---

run "managed_mode_creates_network_resources" {
  command = plan

  assert {
    condition     = length(oci_core_vcn.cloudscanner_vcn) == 1
    error_message = "Managed mode must create exactly one VCN"
  }
  assert {
    condition     = length(oci_core_subnet.cloudscanner_regional_subnet) == 1
    error_message = "Managed mode must create exactly one subnet"
  }
  assert {
    condition     = length(oci_core_route_table.cloudscanner_route_tables) == 1
    error_message = "Managed mode must create exactly one route table"
  }
  assert {
    condition     = length(oci_core_nat_gateway.cloudscanner_nat) == 1
    error_message = "Managed mode must create exactly one NAT gateway"
  }
  assert {
    condition     = length(oci_core_security_list.cloudscanner_security_list) == 1
    error_message = "Managed mode must create exactly one security list"
  }
  # The custom security list must be explicitly attached to the subnet (exactly
  # one entry) rather than falling back to the all-allow VCN default list.
  assert {
    condition     = length(oci_core_subnet.cloudscanner_regional_subnet[0].security_list_ids) == 1
    error_message = "Managed subnet must attach exactly the module's custom security list"
  }
  assert {
    condition     = length(data.oci_core_subnet.provided) == 0
    error_message = "Managed mode must not look up a provided subnet"
  }
}

# --- Bring-your-own-network mode: no managed network resources ---

run "byo_mode_creates_no_network_resources" {
  command = plan
  variables {
    create_network = false
    vcn_id         = "ocid1.vcn.oc1..mockvcn"
    subnet_id      = "ocid1.subnet.oc1..provided"
  }

  assert {
    condition     = length(oci_core_vcn.cloudscanner_vcn) == 0
    error_message = "BYO mode must not create a VCN"
  }
  assert {
    condition     = length(oci_core_subnet.cloudscanner_regional_subnet) == 0
    error_message = "BYO mode must not create a subnet"
  }
  assert {
    condition     = length(oci_core_route_table.cloudscanner_route_tables) == 0
    error_message = "BYO mode must not create a route table"
  }
  assert {
    condition     = length(oci_core_nat_gateway.cloudscanner_nat) == 0
    error_message = "BYO mode must not create a NAT gateway"
  }
  assert {
    condition     = length(oci_core_security_list.cloudscanner_security_list) == 0
    error_message = "BYO mode must not create a security list"
  }
  # Instances must be placed in the provided subnet, in both places the subnet is
  # wired in: the instance configuration's VNIC and the instance pool placement.
  assert {
    condition     = oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].create_vnic_details[0].subnet_id == "ocid1.subnet.oc1..provided"
    error_message = "BYO mode must place the instance configuration VNIC in the provided subnet"
  }
  assert {
    condition     = oci_core_instance_pool.cloudscanner_instance_pool.placement_configurations[0].primary_vnic_subnets[0].subnet_id == "ocid1.subnet.oc1..provided"
    error_message = "BYO mode must place the instance pool in the provided subnet"
  }
}

# --- Validation: subnet must belong to the provided VCN ---

run "byo_mode_rejects_subnet_in_wrong_vcn" {
  command = plan
  variables {
    create_network = false
    vcn_id         = "ocid1.vcn.oc1..differentvcn"
    subnet_id      = "ocid1.subnet.oc1..provided"
  }
  expect_failures = [oci_core_instance_configuration.cloudscanner_instance_configuration]
}

# --- Validation: create_network = false requires both subnet_id and vcn_id ---

run "byo_mode_rejects_subnet_without_vcn" {
  command = plan
  variables {
    create_network = false
    subnet_id      = "ocid1.subnet.oc1..provided"
  }
  expect_failures = [oci_core_instance_configuration.cloudscanner_instance_configuration]
}

run "byo_mode_rejects_vcn_without_subnet" {
  command = plan
  variables {
    create_network = false
    vcn_id         = "ocid1.vcn.oc1..mockvcn"
  }
  expect_failures = [oci_core_instance_configuration.cloudscanner_instance_configuration]
}

run "byo_mode_rejects_create_network_false_with_no_network" {
  command = plan
  variables {
    create_network = false
  }
  expect_failures = [oci_core_instance_configuration.cloudscanner_instance_configuration]
}

# --- Validation: create_network = true (managed) rejects a provided network ---

run "managed_mode_rejects_provided_subnet" {
  command = plan
  variables {
    create_network = true
    vcn_id         = "ocid1.vcn.oc1..mockvcn"
    subnet_id      = "ocid1.subnet.oc1..provided"
  }
  expect_failures = [oci_core_instance_configuration.cloudscanner_instance_configuration]
}

# --- Validation: OCID format ---

run "rejects_invalid_subnet_ocid" {
  command = plan
  variables {
    create_network = false
    vcn_id         = "ocid1.vcn.oc1..mockvcn"
    subnet_id      = "not-an-ocid"
  }
  expect_failures = [var.subnet_id]
}

run "rejects_invalid_vcn_ocid" {
  command = plan
  variables {
    create_network = false
    vcn_id         = "not-an-ocid"
    subnet_id      = "ocid1.subnet.oc1..provided"
  }
  expect_failures = [var.vcn_id]
}
