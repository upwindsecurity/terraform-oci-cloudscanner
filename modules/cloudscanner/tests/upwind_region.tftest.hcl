# Validation-only tests for var.upwind_region. Providers are mocked and every
# run is a plan, so no OCI credentials are needed.

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

run "defaults_to_us" {
  command = plan

  assert {
    condition     = var.upwind_region == "us"
    error_message = "upwind_region should default to 'us'"
  }
}

run "accepts_us" {
  command = plan
  variables { upwind_region = "us" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=us ")
    error_message = "upwind_region 'us' was not passed to the startup script"
  }
}

run "accepts_eu" {
  command = plan
  variables { upwind_region = "eu" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=eu ")
    error_message = "upwind_region 'eu' was not passed to the startup script"
  }
}

run "accepts_ap" {
  command = plan
  variables { upwind_region = "ap" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=ap ")
    error_message = "upwind_region 'ap' was not passed to the startup script"
  }
}

run "accepts_me" {
  command = plan
  variables { upwind_region = "me" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=me ")
    error_message = "upwind_region 'me' was not passed to the startup script"
  }
}

run "accepts_pdc01" {
  command = plan
  variables { upwind_region = "pdc01" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=pdc01 ")
    error_message = "upwind_region 'pdc01' was not passed to the startup script"
  }
}

run "accepts_pdc02" {
  command = plan
  variables { upwind_region = "pdc02" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=pdc02 ")
    error_message = "upwind_region 'pdc02' was not passed to the startup script"
  }
}

run "rejects_pdc_with_one_digit" {
  command = plan
  variables { upwind_region = "pdc1" }
  expect_failures = [var.upwind_region]
}

run "rejects_pdc_with_three_digits" {
  command = plan
  variables { upwind_region = "pdc001" }
  expect_failures = [var.upwind_region]
}

run "rejects_pdc_with_non-digits" {
  command = plan
  variables { upwind_region = "pdcab" }
  expect_failures = [var.upwind_region]
}

run "rejects_uppercase_pdc" {
  command = plan
  variables { upwind_region = "PDC01" }
  expect_failures = [var.upwind_region]
}

run "rejects_uppercase_us" {
  command = plan
  variables { upwind_region = "US" }
  expect_failures = [var.upwind_region]
}

run "rejects_trailing_whitespace" {
  command = plan
  variables { upwind_region = "pdc01 " }
  expect_failures = [var.upwind_region]
}

run "rejects_leading_characters" {
  command = plan
  variables { upwind_region = "xpdc01" }
  expect_failures = [var.upwind_region]
}

run "rejects_pdc_without_digits" {
  command = plan
  variables { upwind_region = "pdc" }
  expect_failures = [var.upwind_region]
}

run "rejects_unknown_region" {
  command = plan
  variables { upwind_region = "xx" }
  expect_failures = [var.upwind_region]
}

run "rejects_empty_string" {
  command = plan
  variables { upwind_region = "" }
  expect_failures = [var.upwind_region]
}

# pdcXX regions beyond pdc01/pdc02 are accepted by the regex validation.
run "accepts_pdc03" {
  command = plan
  variables { upwind_region = "pdc03" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=pdc03 ")
    error_message = "upwind_region 'pdc03' was not passed to the startup script"
  }
}

run "accepts_pdc07" {
  command = plan
  variables { upwind_region = "pdc07" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=pdc07 ")
    error_message = "upwind_region 'pdc07' was not passed to the startup script"
  }
}

run "accepts_pdc99" {
  command = plan
  variables { upwind_region = "pdc99" }

  assert {
    condition     = strcontains(base64decode(oci_core_instance_configuration.cloudscanner_instance_configuration.instance_details[0].launch_details[0].metadata.user_data), "UPWIND_INFRA_REGION=pdc99 ")
    error_message = "upwind_region 'pdc99' was not passed to the startup script"
  }
}
