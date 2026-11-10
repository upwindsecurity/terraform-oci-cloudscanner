
locals {
  vpc_cidr       = "192.168.0.0/16"
  subnet_cidr    = "192.168.1.0/24"
  scanner_suffix = replace(var.scanner_id, "ucsc-", "")
  # DNS label must be 15 characters or less
  scanner_dns_label = substr(lower(replace("${var.oracle_region}${local.scanner_suffix}", "-", "")), 0, 15)

  # The subnet instances are placed in: the module-managed subnet when
  # create_network is true, otherwise the caller-provided subnet. Gating on the
  # create_network bool (rather than on subnet_id) keeps resource counts known at
  # plan time even when subnet_id is a value computed in the same apply.
  effective_subnet_id = var.create_network ? one(oci_core_subnet.cloudscanner_regional_subnet[*].id) : var.subnet_id
}

# Lookup of the caller-provided subnet, used to validate it belongs to var.vcn_id.
# Queried whenever a subnet_id is provided; gated on subnet_id (not create_network)
# so it never indexes an unused resource.
data "oci_core_subnet" "provided" {
  count     = var.subnet_id != "" ? 1 : 0
  subnet_id = var.subnet_id
}

resource "oci_core_vcn" "cloudscanner_vcn" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = [local.vpc_cidr]

  display_name = "${var.scanner_id}-VCN"

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
  dns_label     = local.scanner_dns_label
}

# Subnet - Regional subnet (across the whole region and not specific ADs)
resource "oci_core_subnet" "cloudscanner_regional_subnet" {
  count          = var.create_network ? 1 : 0
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
  count          = var.create_network ? 1 : 0
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
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id

  freeform_tags = local.freeform_tags
  defined_tags  = local.validated_defined_tags
  display_name  = "${var.scanner_id}-NATGateway"
}

# Security List - AWS SG rules

resource "oci_core_security_list" "cloudscanner_security_list" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn[0].id
  display_name   = "${var.scanner_id}-SecurityList"

  # Allow all traffic inside VCN
  ingress_security_rules {
    source   = local.vpc_cidr
    protocol = "all"
  }

  # ICMP "fragmentation needed" (type 3, code 4) from anywhere. Mirrors OCI's
  # default security list so path-MTU discovery keeps working; without it, PMTUD
  # breaks and large packets can silently stall. (OCI's default list is replaced
  # once a custom security list is attached to the subnet, so this is re-added.)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1" # ICMP
    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP "destination unreachable" (type 3) from within the VCN, also mirroring
  # OCI's default security list.
  ingress_security_rules {
    source   = local.vpc_cidr
    protocol = "1" # ICMP
    icmp_options {
      type = 3
    }
  }

  # Allow all outbound inside VCN
  egress_security_rules {
    destination = local.vpc_cidr
    protocol    = "all"
  }

  # Outbound HTTP (TCP 80).
  # Open question: it is not yet confirmed whether the scanner actually needs
  # plain HTTP, or whether all egress can go over HTTPS (443) and this rule can
  # be dropped. Kept for now so existing deployments are not broken.
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6" # TCP
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Outbound HTTPS (TCP 443) - CloudScanner download, registry pulls, OCI and
  # Upwind API traffic.
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
