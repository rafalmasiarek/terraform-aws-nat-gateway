## Terraform Reference



### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_tagger"></a> [tagger](#requirement\_tagger) | >= 0.1.0 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bandwidth_utilization"></a> [bandwidth\_utilization](#module\_bandwidth\_utilization) | rafalmasiarek/cloudwatch/aws//modules/metric-alarm | >= 0.1.0 |
| <a name="module_error_port_allocation"></a> [error\_port\_allocation](#module\_error\_port\_allocation) | rafalmasiarek/cloudwatch/aws//modules/metric-alarm | >= 0.1.0 |
| <a name="module_estimated_data_processing_cost"></a> [estimated\_data\_processing\_cost](#module\_estimated\_data\_processing\_cost) | rafalmasiarek/cloudwatch/aws//modules/metric-alarm | >= 0.1.0 |
| <a name="module_packets_drop"></a> [packets\_drop](#module\_packets\_drop) | rafalmasiarek/cloudwatch/aws//modules/metric-alarm | >= 0.1.0 |
| <a name="module_tagger"></a> [tagger](#module\_tagger) | rafalmasiarek/tagger/null | >= 0.5.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [aws_eip.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| tagger_origin.self | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarms"></a> [alarms](#input\_alarms) | CloudWatch alarms for every NAT gateway this module creates. Each key is independently<br/>toggled via its own `enabled`. error\_port\_allocation and packets\_drop mirror AWS's own<br/>"Recommended Alarms" for AWS/NATGateway (see<br/>https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html).<br/>bandwidth\_utilization and estimated\_data\_processing\_cost are this module's own addition,<br/>built from the same BytesInFromSource/BytesInFromDestination metrics - they estimate<br/>usage from CloudWatch data, which is not the authoritative AWS billing meter and can<br/>differ from your actual bill. | <pre>object({<br/>    error_port_allocation = optional(object({<br/>      enabled             = optional(bool, true)<br/>      period_seconds      = optional(number, 60)<br/>      evaluation_periods  = optional(number, 15)<br/>      datapoints_to_alarm = optional(number, 15)<br/>      alarm_actions       = optional(list(string), [])<br/>      ok_actions          = optional(list(string), [])<br/>    }), {})<br/><br/>    packets_drop = optional(object({<br/>      enabled             = optional(bool, false) # off by default - no safe universal threshold to default to, see the validation below<br/>      threshold           = optional(number)      # no safe universal default - AWS: derive from your own traffic history (~0.01% of total traffic)<br/>      period_seconds      = optional(number, 60)<br/>      evaluation_periods  = optional(number, 5)<br/>      datapoints_to_alarm = optional(number, 5)<br/>      alarm_actions       = optional(list(string), [])<br/>      ok_actions          = optional(list(string), [])<br/>    }), {})<br/><br/>    bandwidth_utilization = optional(object({<br/>      enabled              = optional(bool, false)<br/>      threshold_percent    = optional(number, 80)<br/>      bandwidth_limit_gbps = optional(number, 100) # AWS's current documented per-NAT-gateway ceiling - override if AWS changes it<br/>      period_seconds       = optional(number, 300)<br/>      evaluation_periods   = optional(number, 3)<br/>      datapoints_to_alarm  = optional(number, 3)<br/>      alarm_actions        = optional(list(string), [])<br/>      ok_actions           = optional(list(string), [])<br/>    }), {})<br/><br/>    estimated_data_processing_cost = optional(object({<br/>      enabled = optional(bool, false)<br/>      # NAT gateway's own per-GB fee - applies to all data it processes,<br/>      # both directions. No safe universal default - varies by region/contract.<br/>      price_per_gb_processed = optional(number)<br/>      # Standard AWS "data transfer OUT to the internet" fee - applies only<br/>      # to the egress direction (traffic AWS sends to the internet); AWS<br/>      # never charges for the inbound/ingress direction. Defaults to 0 (not<br/>      # modeled) rather than requiring it, since some callers only want the<br/>      # NAT processing fee estimated.<br/>      price_per_gb_data_transfer_out = optional(number, 0)<br/>      monthly_budget_usd             = optional(number) # no safe universal default - your own budget<br/>      period_seconds                 = optional(number, 3600)<br/>      evaluation_periods             = optional(number, 1)<br/>      datapoints_to_alarm            = optional(number, 1)<br/>      alarm_actions                  = optional(list(string), [])<br/>      ok_actions                     = optional(list(string), [])<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_nat_gateways"></a> [nat\_gateways](#input\_nat\_gateways) | One aws\_nat\_gateway per entry, typically keyed by AZ (e.g. "a", "b"), one per AZ for HA egress. connectivity\_type = "public" (default) gets its own aws\_eip unless allocation\_id is set; "private" gets neither (no internet access, routes between VPCs/on-prem only - see AWS's private NAT gateway docs). | <pre>map(object({<br/>    subnet_id                = string<br/>    connectivity_type        = optional(string, "public") # "public" | "private"<br/>    allocation_id            = optional(string)           # bring your own EIP; ignored for "private"<br/>    secondary_allocation_ids = optional(list(string), []) # extra EIPs for automatic port scaling; "public" only<br/>    private_ip               = optional(string)           # "private" only - fixed private IP instead of an auto-assigned one<br/>  }))</pre> | n/a | yes |
| <a name="input_price_per_hour"></a> [price\_per\_hour](#input\_price\_per\_hour) | Estimated on-demand hourly price per NAT gateway, used only for the estimated\_hourly\_cost output - varies by region and contract (EDP/PPA), this module never looks it up itself. Leave null to skip the output. | `number` | `null` | no |
| <a name="input_tagger_additional_services"></a> [tagger\_additional\_services](#input\_tagger\_additional\_services) | Extra terraform-null-tagger `service` data per taggable resource, keyed by the same key as local.taggable (e.g. "subnet-public-a"). Merged on top of what this module computes automatically - lets a caller tag something this module doesn't know about, without waiting for a new module release. | `any` | `{}` | no |
| <a name="input_tagger_context"></a> [tagger\_context](#input\_tagger\_context) | module.tagger.context from the root stack's base terraform-null-tagger call. | `any` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Custom tags for the resource(s). | `map(string)` | `{}` | no |
| <a name="input_topology_igw_id"></a> [topology\_igw\_id](#input\_topology\_igw\_id) | Internet Gateway id, for the topology\_fragment diagram only - a NAT gateway's own egress to the internet is automatic once an IGW exists in the VPC (no route table entry needed), so this module has no other reason to need it. Omit to leave the nat -> igw edge undrawn. Only applies to connectivity\_type = "public" entries. | `string` | `null` | no |
| <a name="input_use_tagger"></a> [use\_tagger](#input\_use\_tagger) | Compute and apply standardized tags via terraform-null-tagger. When false, use var.tags as-is instead. | `bool` | `true` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_eip_allocation_ids"></a> [eip\_allocation\_ids](#output\_eip\_allocation\_ids) | Allocation id per entry that got an auto-created EIP (connectivity\_type = "public" and no allocation\_id supplied). Entries using a caller-supplied allocation\_id or connectivity\_type = "private" are absent, not null. |
| <a name="output_eip_public_ips"></a> [eip\_public\_ips](#output\_eip\_public\_ips) | Public IP per entry that got an auto-created EIP. Same absence rule as eip\_allocation\_ids. |
| <a name="output_estimated_hourly_cost"></a> [estimated\_hourly\_cost](#output\_estimated\_hourly\_cost) | Number of NAT gateways times var.price\_per\_hour. null when price\_per\_hour is null. Not the authoritative AWS bill - the data-processing component isn't included here, see the estimated\_data\_processing\_cost alarm for that. |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | n/a |
| <a name="output_nat_gateway_network_interface_ids"></a> [nat\_gateway\_network\_interface\_ids](#output\_nat\_gateway\_network\_interface\_ids) | n/a |
| <a name="output_topology_fragment"></a> [topology\_fragment](#output\_topology\_fragment) | Network topology fragment for composition with sibling modules via provider::netutils::mermaid\_merge(). See terraform-provider-netutils's docs/topology-fragment-spec.md. |