# CloudScanner Module

## Overview
Terraform module to deploy Upwind CloudScanner resources into Oracle Cloud Infrastructure (OCI). Creates networking (VCN, subnet, NAT, route table, security list), instance configuration and instance pool, KMS vault/key and a secret to store Upwind credentials.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |

## Providers

| Name | Version |
|------|---------|
| `oci` | (used by the module via `provider "oci"`) |
| `null` | >= 3.0.0 |
| `random` | >= 3.0.0 |
| `time` | >= 0.7.0 |

## Modules

No modules.

## Resources
Key resources created by this module:

- `oci_core_vcn.cloudscanner_vcn` - Virtual Cloud Network
- `oci_core_subnet.cloudscanner_regional_subnet` - Regional subnet
- `oci_core_route_table.cloudscanner_route_tables` - Route table with NAT gateway route
- `oci_core_nat_gateway.cloudscanner_nat` - NAT gateway for private outbound traffic
- `oci_core_security_list.cloudscanner_security_list` - Security list (firewall rules)
- `oci_core_instance_configuration.cloudscanner_instance_configuration` - Instance configuration
- `oci_core_instance_pool.cloudscanner_instance_pool` - Auto-scaling instance pool
- `null_resource.always_run` - Trigger for lifecycle management

## Vault Secret Naming

This module automatically discovers secrets in the OCI Vault specified by `upwind_vault_id` by matching on a prefix pattern.

The module looks for secrets with names starting with:
- `upwind-client-id-<last5chars>-*` - Upwind OAuth client ID
- `upwind-client-secret-<last5chars>-*` - Upwind OAuth client secret

Where `<last5chars>` are the last 5 characters of your `upwind_org_id` (converted to lowercase).

The 8-character suffix after the last 5 characters can be any value - the module will automatically find and use the matching secrets.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------:|:-------:|:--------:|
| `oracle_region` | The Oracle region of the deployed resources. | `string` | n/a | yes |
| `auth_token` | Oracle Auth Token used for authenticating against OCR for image scans. | `string` | n/a | yes |
| `availability_zones` | The zones within the region that will be used. If not provided, all availability domains in the region will be used. | `list(any)` | `[]` | no |
| `compartment_id` | The root compartment where CloudScanner is deployed. | `string` | n/a | yes |
| `tenancy_id` | The OCI tenancy OCID for querying platform images. If not provided, compartment_id will be used. | `string` | `""` | no |
| `upwind_vault_id` | OCID of the existing OCI Vault that contains the Upwind OAuth secrets. | `string` | n/a | yes |
| `object_namespace` | The object namespace associated with the tenancy. | `string` | n/a | yes |
| `account_user` | The Service Account User required for image scans. | `string` | n/a | yes |
| `scanner_id` | The Upwind Scanner ID. | `string` | n/a | yes |
| `upwind_org_id` | The Upwind Organization ID. The last 5 characters (lowercase) are used as a prefix to match vault secrets. | `string` | n/a | yes |
| `upwind_region` | Which Upwind region to communicate with: `us`, `eu`, `me`, or `pdc01`. | `string` | `us` | no |
| `target_size` | Target size of the instance pool. | `number` | `10` | no |
| `public_uri_domain` | The public URI domain. | `string` | `upwind.io` | no |
| `extra_tags` | Map of tags applied to resources. | `map(string)` | `{}` | no |
| `shape` | Shape of the CloudScanner worker VM. | `string` | `VM.Standard.E5.Flex` | no |
| `boot_volume_size` | Boot size for VM disk in GB. | `number` | `50` | no |
| `ocpus` | Number of OCPUs for flexible shapes. Must be `>= 1`. | `number` | `4` | no |
| `memory_in_gbs` | Memory in GB for flexible shapes. Must satisfy: `memory_in_gbs >= ocpus` and `(memory_in_gbs / ocpus)` in `[1..64]`. | `number` | `4` | no |

Notes:

- The module detects flexible shapes by checking if `flex` is present in the `shape` string. When using an OCI flexible shape (e.g. `VM.Standard.E5.Flex`) the module will populate `shape_config` with `ocpus` and `memory_in_gbs`.
- Validation for `ocpus` and `memory_in_gbs` is implemented in `modules/cloudscanner/variables.tf`. Ensure `memory_in_gbs / ocpus` is between `1` and `64` to avoid OCI API errors.

## Outputs

| Name | Description | Example reference |
|------|-------------|-------------------|
| `oracle_asg_name` | The name of the Cloud Scanner Instance Pool. | `module.cloudscanner.oracle_asg_name` |

