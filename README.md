# terraform-aws-nat-gateway
![](https://raw.githubusercontent.com/rafalmasiarek/readme-gen/main/banners/.gitkeep)

## About

Terraform module for one or more `aws_nat_gateway` resources (one per entry
in `nat_gateways`, typically one per Availability Zone for HA egress), each
with its own `aws_eip` unless you bring your own allocation. It never
creates the VPC, the subnets, or any route table entry pointing at it -
those belong to [terraform-aws-vpc](https://github.com/rafalmasiarek/terraform-aws-vpc)
and [terraform-aws-subnets](https://github.com/rafalmasiarek/terraform-aws-subnets).



## License
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

```text
The MIT License (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, to deal in the Software
without restriction.

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

Source: https://opensource.org/licenses/MIT
```
See [LICENSE](LICENSE) for full details.
## Authors

- Rafał Masiarek | [website](https://masiarek.pl) | [email](mailto:rafal@masiarek.pl) | [github](https://github.com/rafalmasiarek)


## Usage

```hcl
module "nat" {
  source = "git::https://github.com/rafalmasiarek/terraform-aws-nat-gateway.git?ref=v0.1.0"

  nat_gateways = {
    a = { subnet_id = module.subnets.subnet_ids["public-a"] }
    b = { subnet_id = module.subnets.subnet_ids["public-b"] }
  }

  tagger_context = module.tagger.context
}
```

## Private NAT gateways

`connectivity_type = "private"` has no internet access and no Elastic IP -
it only routes between VPCs, a Transit Gateway, or on-premises over a VPN/
Direct Connect. Set a fixed `private_ip` if you need one; otherwise AWS
assigns one automatically. `allocation_id`/`secondary_allocation_ids` don't
apply and are rejected by this module's own validation if set.

## Ingress/egress

NAT gateway metrics - and this module's cost estimate - distinguish two
directions, because AWS bills them differently:

- **egress** (`BytesInFromSource`) - traffic the NAT gateway received from
  your VPC clients, bound for the internet. Carries both the NAT gateway's
  own per-GB processing fee and the standard AWS "data transfer OUT to the
  internet" fee.
- **ingress** (`BytesInFromDestination`) - traffic the NAT gateway received
  from the internet destination, i.e. responses coming back. Carries only
  the NAT gateway's own per-GB processing fee - AWS never charges for data
  transfer *into* AWS from the internet.

`estimated_data_processing_cost` (below) models this directly:
`price_per_gb_processed` applies to `egress + ingress`,
`price_per_gb_data_transfer_out` applies to `egress` only. A private NAT
gateway never reaches the internet, so the data-transfer-out term is
always zeroed for one, regardless of what you set.

## Alarms

```hcl
alarms = {
  error_port_allocation = { enabled = true }  # default
  packets_drop = {
    enabled   = true
    threshold = 50  # AWS: derive this from your own traffic history
  }
  bandwidth_utilization = {
    enabled           = true
    threshold_percent = 80
  }
  estimated_data_processing_cost = {
    enabled                        = true
    price_per_gb_processed         = 0.045 # NAT's own fee, both directions
    price_per_gb_data_transfer_out = 0.09  # standard AWS egress fee, outbound only - optional, defaults to 0 (not modeled)
    monthly_budget_usd             = 500
  }
}
```

`error_port_allocation` and `packets_drop` mirror AWS's own ["Recommended
Alarms" for `AWS/NATGateway`](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html):

- **`error_port_allocation`** (on by default - threshold `0` is AWS's own
  fixed recommendation, no situational input needed) - the NAT gateway
  couldn't allocate a source port for a new connection, almost always too
  many concurrent connections to one popular destination.
- **`packets_drop`** (off by default - `threshold` has no safe universal
  default; AWS's own guidance is to derive it from ~0.01% of your own
  historical traffic) - the NAT gateway is dropping packets, which can
  happen past its documented ceiling of 10M packets/sec.

`bandwidth_utilization` and `estimated_data_processing_cost` are this
module's own addition, not an AWS recommendation - both are CloudWatch-derived
estimates from the same `BytesInFromSource`/`BytesInFromDestination` metrics,
**not** the authoritative AWS billing meter, and can differ from your actual
bill:

- **`bandwidth_utilization`** (off by default) - estimated throughput as a
  percentage of `bandwidth_limit_gbps` (default `100`, AWS's current
  documented per-NAT-gateway ceiling - a NAT gateway auto-scales from a
  5 Gbps baseline up to this). Approaching it is AWS's own suggested signal
  to split traffic across more subnets/NAT gateways.
- **`estimated_data_processing_cost`** (off by default) - projects a
  full-month cost from the same bytes metrics, split by direction - see
  [Ingress/egress](#ingressegress) - and alarms when it's on pace to exceed
  `monthly_budget_usd`. NAT gateway billing overall has two components - an
  hourly charge (`estimated_hourly_cost` output, deterministic, no metric
  needed) and this per-GB-processed one (the usual source of bill
  surprises).

Every alarm takes its own `alarm_actions`/`ok_actions` (e.g. an SNS topic
ARN) - this module never creates its own SNS topic or dashboard, consistent
with every other module in this family (config comes from the caller).

If most of your traffic through a NAT gateway is to AWS services that
support VPC endpoints (S3, DynamoDB, ECR, SSM, ...), that traffic can skip
the NAT gateway - and its per-GB charge - entirely once routed through an
endpoint instead. That's a separate module's job, not this one's.

## Topology

`topology_fragment` composes with sibling modules via
`provider::netutils::mermaid_merge()` - see
[terraform-provider-netutils's docs/topology-fragment-spec.md](https://github.com/rafalmasiarek/terraform-provider-netutils/blob/main/docs/topology-fragment-spec.md).
Each NAT gateway nests under its own `subnet_id`. A NAT gateway's own egress
to the internet is automatic once an IGW exists in the VPC (no route table
entry needed) - this module has no other reason to need `var.topology_igw_id`,
so it stays optional, topology-only, and unused by any actual resource here.
Private NAT gateways never draw that edge, regardless of `topology_igw_id`.


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


<!-- references -->

[repo_link]: https://github.com/rafalmasiarek/terraform-aws-nat-gateway
