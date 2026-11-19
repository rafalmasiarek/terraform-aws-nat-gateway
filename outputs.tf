output "nat_gateway_ids" {
  value = { for k, v in aws_nat_gateway.this : k => v.id }
}

output "nat_gateway_network_interface_ids" {
  value = { for k, v in aws_nat_gateway.this : k => v.network_interface_id }
}

output "eip_allocation_ids" {
  description = "Allocation id per entry that got an auto-created EIP (connectivity_type = \"public\" and no allocation_id supplied). Entries using a caller-supplied allocation_id or connectivity_type = \"private\" are absent, not null."
  value       = { for k, v in aws_eip.this : k => v.id }
}

output "eip_public_ips" {
  description = "Public IP per entry that got an auto-created EIP. Same absence rule as eip_allocation_ids."
  value       = { for k, v in aws_eip.this : k => v.public_ip }
}

output "estimated_hourly_cost" {
  description = "Number of NAT gateways times var.price_per_hour. null when price_per_hour is null. Not the authoritative AWS bill - the data-processing component isn't included here, see the estimated_data_processing_cost alarm for that."
  value       = var.price_per_hour != null ? length(var.nat_gateways) * var.price_per_hour : null
}

output "topology_fragment" {
  description = "Network topology fragment for composition with sibling modules via provider::netutils::mermaid_merge(). See terraform-provider-netutils's docs/topology-fragment-spec.md."
  value       = local.topology_fragment
}
