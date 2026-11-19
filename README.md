# terraform-aws-nat-gateway

Terraform module for one or more `aws_nat_gateway` resources (one per entry
in `nat_gateways`, typically one per Availability Zone for HA egress), each
with its own `aws_eip` unless you bring your own allocation. It never
creates the VPC, the subnets, or any route table entry pointing at it -
those belong to [terraform-aws-vpc](https://github.com/rafalmasiarek/terraform-aws-vpc)
and [terraform-aws-subnets](https://github.com/rafalmasiarek/terraform-aws-subnets).

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

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `nat_gateways` | `map(object)` | - | One `aws_nat_gateway` per entry. `subnet_id` (required), `connectivity_type` (`"public"` default or `"private"`), `allocation_id` (bring your own EIP, `"public"` only), `secondary_allocation_ids` (`"public"` only), `private_ip` (`"private"` only). |
| `topology_igw_id` | `string` | `null` | Internet Gateway id, for the `topology_fragment` diagram only - see [Topology](#topology). |
| `price_per_hour` | `number` | `null` | Estimated on-demand hourly price per NAT gateway, for `estimated_hourly_cost` only. |
| `alarms` | `object` | see [Alarms](#alarms) | CloudWatch alarms, one set of toggles/thresholds shared by every entry in `nat_gateways`. |
| `use_tagger` | `bool` | `true` | `false` applies `var.tags` as-is instead. |
| `tagger_context` | `any` | `null` | `module.tagger.context` from the root stack. |
| `tags` | `map(string)` | `{}` | Custom tags for the resources. |

## Outputs

| Name | Description |
|---|---|
| `nat_gateway_ids` | Map keyed by `nat_gateways` key. |
| `nat_gateway_network_interface_ids` | Map keyed by `nat_gateways` key. |
| `eip_allocation_ids` | Map keyed by `nat_gateways` key - only entries with an auto-created EIP (see [Inputs](#inputs)). |
| `eip_public_ips` | Same key set as `eip_allocation_ids`. |
| `estimated_hourly_cost` | `length(nat_gateways) * price_per_hour`, or `null` if `price_per_hour` is unset. |
| `topology_fragment` | See [Topology](#topology). |

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
