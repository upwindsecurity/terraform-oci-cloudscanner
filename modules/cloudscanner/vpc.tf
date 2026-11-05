
locals {
  vpc_cidr       = "192.168.0.0/16"
  subnet_cidr    = "192.168.1.0/24"
  scanner_suffix = replace(var.scanner_id, "ucsc-", "")
  # DNS label must be 15 characters or less
  scanner_dns_label = substr(lower(replace("${var.oracle_region}${local.scanner_suffix}", "-", "")), 0, 15)

  # Bring-your-own-network mode is enabled when the caller provides a subnet_id.
  # In that mode the module creates none of the managed network resources below and
  # places instances in the provided subnet instead.
  manage_network = var.subnet_id == ""

  # The subnet instances are placed in: the caller-provided subnet in BYO mode,
  # otherwise the subnet this module creates.
  effective_subnet_id = var.subnet_id != "" ? var.subnet_id : oci_core_subnet.cloudscanner_regional_subnet[0].id
}

# Lookup of the caller-provided subnet, used to validate it belongs to var.vcn_id.
# Only queried in bring-your-own-network mode.
data "oci_core_subnet" "provided" {
  count     = var.subnet_id != "" ? 1 : 0
  subnet_id = var.subnet_id
}

resource "oci_core_vcn" "cloudscanner_vcn" {
  count          = local.manage_network ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = [local.vpc_cidr]

  display_name = "${var.scanner_id}-VCN"

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
  dns_label     = local.scanner_dns_label
}

# Subnet - Regional subnet (across the whole region and not specific ADs)
resource "oci_core_subnet" "cloudscanner_regional_subnet" {
  count          = local.manage_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id
  cidr_block     = local.subnet_cidr
  display_name   = "${var.scanner_id}-RegionalSubnet"

  prohibit_public_ip_on_vnic = true
  dns_label                  = local.scanner_dns_label

  freeform_tags  = local.freeform_tags
  defined_tags   = local.validated_defined_tags
  route_table_id = oci_core_route_table.cloudscanner_route_tables[0].id
  # Attach the module's custom security list. Without this the subnet would fall
  # back to the VCN default security list (all-allow egress), leaving the custom
  # egress rules below orphaned.
  security_list_ids = [oci_core_security_list.cloudscanner_security_list[0].id]
}

# Route tables (Contains the IGW, NAT, SG rules)
resource "oci_core_route_table" "cloudscanner_route_tables" {
  count          = local.manage_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id

  # NAT for private workloads
  route_rules {
    network_entity_id = oci_core_nat_gateway.cloudscanner_nat[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
  display_name  = "${var.scanner_id}-CoreRouteTable"
}

# NAT Gateway - for private outbound traffic

resource "oci_core_nat_gateway" "cloudscanner_nat" {
  count          = local.manage_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
  display_name  = "${var.scanner_id}-NATGateway"
}

# Security List - AWS SG rules

resource "oci_core_security_list" "cloudscanner_security_list" {
  count          = local.manage_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id
  display_name   = "${var.scanner_id}-SecurityList"

  # Allow all traffic inside VCN
  ingress_security_rules {
    source   = local.vpc_cidr
    protocol = "all"
  }

  # Allow all outbound inside VCN
  egress_security_rules {
    destination = local.vpc_cidr
    protocol    = "all"
  }

  # Outbound 80
  # TODO(UP-12645 / D3): confirm whether TCP/80 is actually required, or whether
  # all CloudScanner egress can go over 443 and this rule can be removed.
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6" # TCP
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Outbound 443
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6" # TCP
    tcp_options {
      min = 443
      max = 443
    }
  }

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
}
