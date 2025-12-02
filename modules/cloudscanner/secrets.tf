locals {
  credentials = jsonencode({
    clientId     = trimspace(var.upwind_client_id)
    clientSecret = trimspace(var.upwind_client_secret)
  })
}

# Base64 encode the JSON (OCI requires base64 content)
locals {
  encoded_credentials = base64encode(local.credentials)
}

# small pause to allow vault management endpoint to become resolvable
resource "time_sleep" "wait_for_vault" {
  depends_on      = [oci_kms_vault.upwind_vault]
  create_duration = "30s"
}

