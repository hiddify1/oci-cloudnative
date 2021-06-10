# Copyright (c) 2021 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

resource "oci_identity_dynamic_group" "oke_nodes_dg" {
  name           = "${local.app_name_normalized}-oke-cluster-dg-${random_string.deploy_id.result}"
  description    = "${var.app_name} Cluster Dynamic Group"
  compartment_id = var.tenancy_ocid
  matching_rule  = "ANY {${join(",",local.dynamic_group_matching_rules)}}"

  provider = oci.home_region

  count = var.create_dynamic_group_for_nodes_in_compartment ? 1 : 0
}
resource "oci_identity_policy" "oke_compartment_policies" {
  name           = "${local.app_name_normalized}-oke-cluster-compartment-policies-${random_string.deploy_id.result}"
  description    = "${var.app_name} Compartment Policies (${random_string.deploy_id.result})"
  compartment_id = local.oke_compartment_ocid
  statements     = local.oke_compartment_statements

  depends_on = [oci_identity_dynamic_group.oke_nodes_dg]

  provider = oci.home_region

  count = var.create_compartment_policies ? 1 : 0
}
resource "oci_identity_policy" "kms_compartment_policies" {
  name           = "${local.app_name_normalized}-kms-compartment-policies-${random_string.deploy_id.result}"
  description    = "${var.app_name} KMS Compartment Policies (${random_string.deploy_id.result})"
  compartment_id = local.oke_compartment_ocid
  statements     = local.kms_compartment_statements

  depends_on = [oci_identity_dynamic_group.oke_nodes_dg]

  provider = oci.home_region

  count = (var.create_compartment_policies && var.create_vault_policies_for_group) ? 1 : 0
}

resource "oci_identity_policy" "oke_tenancy_policies" {
  name           = "${local.app_name_normalized}-oke-cluster-tenancy-policies-${random_string.deploy_id.result}"
  description    = "${var.app_name} Tenancy Policies (${random_string.deploy_id.result})"
  compartment_id = var.tenancy_ocid
  statements     = local.oke_tenancy_statements

  depends_on = [oci_identity_dynamic_group.oke_nodes_dg]

  provider = oci.home_region

  count = var.create_tenancy_policies ? 1 : 0
}

# Concat Matching Rules and Policy Statements
locals {
  dynamic_group_matching_rules = concat(
    local.instances_in_compartment_rule,
    local.clusters_in_compartment_rule,
    var.newsletter_subscription_enabled ? local.functions_in_compartment_rule : [],
    var.newsletter_subscription_enabled ? local.api_gateways_in_compartment_rule : []
  )
  oke_tenancy_statements = concat(
    local.oci_grafana_metrics_statements
  )
  oke_compartment_statements = concat(
    local.oci_grafana_logs_statements,
    var.use_encryption_from_oci_vault ? local.allow_oke_use_oci_vault_keys_statements : [],
    var.cluster_autoscaler_enabled ? local.cluster_autoscaler_statements : [],
    var.create_vault_policies_for_group ? local.allow_group_manage_vault_keys_statements : [],
    var.newsletter_subscription_enabled ? local.functions_statements : [],
    var.newsletter_subscription_enabled ? local.allow_service_user_group_use_email_statements : []
  )
}

# Individual Rules
locals {
  instances_in_compartment_rule = ["ALL {instance.compartment.id = '${local.oke_compartment_ocid}'}"]
  clusters_in_compartment_rule = ["ALL {resource.type = 'cluster', resource.compartment.id = '${local.oke_compartment_ocid}'}"]
  functions_in_compartment_rule = ["ALL {resource.type = 'fnfunc', resource.compartment.id = '${local.oke_compartment_ocid}'}"]
  api_gateways_in_compartment_rule = ["ALL {resource.type = 'ApiGateway', resource.compartment.id = '${local.oke_compartment_ocid}'}"]
}

# Individual Policy Statements
locals {
  oci_grafana_metrics_statements = [
    "Allow dynamic-group ${local.oke_nodes_dg} to read metrics in tenancy",
    "Allow dynamic-group ${local.oke_nodes_dg} to read compartments in tenancy"
  ]
  oci_grafana_logs_statements = [
    "Allow dynamic-group ${local.oke_nodes_dg} to read log-groups in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to read log-content in compartment id ${local.oke_compartment_ocid}"
  ]
  cluster_autoscaler_statements = [
    "Allow dynamic-group ${local.oke_nodes_dg} to manage cluster-node-pools in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to manage instance-family in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to use subnets in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to read virtual-network-family in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to use vnics in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to inspect compartments in compartment id ${local.oke_compartment_ocid}"
  ]
  functions_statements = [
    "Allow dynamic-group ${local.oke_nodes_dg} to use virtual-network-family in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to manage public-ips in compartment id ${local.oke_compartment_ocid}",
    "Allow dynamic-group ${local.oke_nodes_dg} to use functions-family in compartment id ${local.oke_compartment_ocid}"
  ]
  allow_oke_use_oci_vault_keys_statements = [
    "Allow service oke to use vaults in compartment id ${local.oke_compartment_ocid}",
    "Allow service oke to use keys in compartment id ${local.oke_compartment_ocid} where target.key.id = '${local.oci_vault_key_id}'",
    "Allow dynamic-group ${local.oke_nodes_dg} to use keys in compartment id ${local.oke_compartment_ocid} where target.key.id = '${local.oci_vault_key_id}'"
  ]
  allow_group_manage_vault_keys_statements = [
    "Allow group ${var.user_admin_group_for_vault_policy} to manage vaults in compartment id ${local.oke_compartment_ocid}",
    "Allow group ${var.user_admin_group_for_vault_policy} to manage keys in compartment id ${local.oke_compartment_ocid}",
    "Allow group ${var.user_admin_group_for_vault_policy} to use key-delegate in compartment id ${local.oke_compartment_ocid}"
  ]
  allow_service_user_group_use_email_statements = [
    "Allow group ${local.oci_service_user_group} to use email-family in compartment id ${local.oke_compartment_ocid}"
  ]
}

# Conditional locals
locals {
  oke_nodes_dg           = var.create_dynamic_group_for_nodes_in_compartment ? oci_identity_dynamic_group.oke_nodes_dg.0.name : "void"
  oci_service_user_group = var.create_oci_service_user ? oci_identity_group.oci_service_user.0.name : "void"
  oci_vault_key_id       = var.use_encryption_from_oci_vault ? (var.create_new_encryption_key ? oci_kms_key.mushop_key[0].id : var.existent_encryption_key_id) : "void"
}
