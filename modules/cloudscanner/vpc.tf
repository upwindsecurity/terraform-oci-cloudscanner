
locals {
  vpc_cidr    = "192.168.0.0/16"
  subnet_cidr = "192.168.1.0/24"
  scanner_dns_label = lower(replace("upwindcs${var.oracle_region}", "-", ""))
}

resource "oci_core_vcn" "cloudscanner_vcn" {
  compartment_id = var.compartment_id
  cidr_blocks    = [local.vpc_cidr]

  display_name = "${local.common_scanner_name}-VCN"

  freeform_tags = local.freeform_tags
  dns_label     = local.scanner_dns_label
}

# Subnet - Regional subnet (across the whole region and not specific ADs)
resource "oci_core_subnet" "cloudscanner_regional_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn.id
  cidr_block     = local.subnet_cidr
  display_name   = "${local.common_scanner_name}-RegionalSubnet"

  prohibit_public_ip_on_vnic = true
  dns_label                  = local.scanner_dns_label

  freeform_tags  = local.freeform_tags
  route_table_id = oci_core_route_table.cloudscanner_route_tables.id
}

# Route tables (Contains the IGW, NAT, SG rules)
resource "oci_core_route_table" "cloudscanner_route_tables" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn.id

  # NAT for private workloads
  route_rules {
    network_entity_id = oci_core_nat_gateway.cloudscanner_nat.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = local.freeform_tags
  display_name  = "${local.common_scanner_name}-CoreRouteTable"
}

# NAT Gateway - for private outbound traffic

resource "oci_core_nat_gateway" "cloudscanner_nat" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn.id

  freeform_tags = local.freeform_tags
  display_name  = "${local.common_scanner_name}-NATGateway"
}

# Security List - AWS SG rules

resource "oci_core_security_list" "cloudscanner_security_list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.cloudscanner_vcn.id
  display_name   = "${local.common_scanner_name}-SecurityList"

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
}

