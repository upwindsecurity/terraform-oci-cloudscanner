output "oracle_asg_name" {
  description = "The name of the Cloud Scanner Instance Pool."
  value = oci_core_instance_pool.cloudscanner_instance_pool.display_name
}
