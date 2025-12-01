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

### 1. Create Vault
resource "oci_kms_vault" "upwind_vault" {
  compartment_id = var.compartment_id
  display_name   = "upwind-vault-${local.common_scanner_name}"
  freeform_tags  = local.freeform_tags
  # TODO: VIRTUAL_PRIVATE, DEFAULT, EXTERNAL - figure out what to use
  vault_type = "DEFAULT"
}

# small pause to allow vault management endpoint to become resolvable
resource "time_sleep" "wait_for_vault" {
  depends_on      = [oci_kms_vault.upwind_vault]
  create_duration = "30s"
}

### 2. Create Master Encryption Key
resource "oci_kms_key" "upwind_key" {
  compartment_id      = var.compartment_id
  display_name        = "upwind-key-${local.common_scanner_name}"
  management_endpoint = oci_kms_vault.upwind_vault.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  freeform_tags = local.freeform_tags
}

### 3. Create the Secret
resource "oci_vault_secret" "upwind_credentials" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.upwind_vault.id
  key_id         = oci_kms_key.upwind_key.id

  secret_name = "upwind-credentials-${local.common_scanner_name}"

  # OCI requires base64-encoded + JSON versioning block
  secret_content {
    content_type = "BASE64"
    name         = "initial"
    content      = local.encoded_credentials
  }

  freeform_tags = merge(local.freeform_tags, {
    Name = "upwind-credentials-${var.scanner_id}"
  })
}

