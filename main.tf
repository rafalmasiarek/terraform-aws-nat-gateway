locals {
  taggable = merge(
    { for k, v in var.nat_gateways : "nat-${k}" => {
      name       = k
      service    = { network = { connectivity_type = v.connectivity_type } }
      attributes = []
      created_at = null
      extra_tags = {}
    } },
    { for k, v in var.nat_gateways : "eip-${k}" => {
      name       = "${k}-eip"
      service    = {}
      attributes = []
      created_at = null
      extra_tags = {}
      } if v.connectivity_type == "public" && v.allocation_id == null
    }
  )

  _eip_targets = { for k, v in var.nat_gateways : k => v if v.connectivity_type == "public" && v.allocation_id == null }

  # CloudWatch alarm_name must be unique per account+region - a bare
  # nat_gateways key (e.g. "a") carries no such guarantee across separate
  # deployments of this module. module.tagger[...].computed_name already is
  # unique (namespace/environment-aware), so alarm names are built from it
  # whenever tagging is on. With use_tagger = false there is no other
  # uniqueness source available, so the key is used as-is and the caller
  # becomes responsible for keeping nat_gateways keys unique across their
  # whole account/region.
  _alarm_name_prefix = {
    for k in keys(var.nat_gateways) :
    k => var.use_tagger ? module.tagger["nat-${k}"].computed_name : k
  }
}

resource "aws_eip" "this" {
  for_each = local._eip_targets

  domain = "vpc"

  tags = local.tagger_tags["eip-${each.key}"]
}

resource "aws_nat_gateway" "this" {
  for_each = var.nat_gateways

  subnet_id                = each.value.subnet_id
  connectivity_type        = each.value.connectivity_type
  allocation_id            = each.value.connectivity_type == "public" ? coalesce(each.value.allocation_id, try(aws_eip.this[each.key].id, null)) : null
  secondary_allocation_ids = length(each.value.secondary_allocation_ids) > 0 ? each.value.secondary_allocation_ids : null
  private_ip               = each.value.private_ip

  tags = local.tagger_tags["nat-${each.key}"]
}

locals {
  _error_port_allocation_targets = var.alarms.error_port_allocation.enabled ? var.nat_gateways : {}
  _packets_drop_targets          = var.alarms.packets_drop.enabled ? var.nat_gateways : {}
  _bandwidth_targets             = var.alarms.bandwidth_utilization.enabled ? var.nat_gateways : {}
  _cost_targets                  = var.alarms.estimated_data_processing_cost.enabled ? var.nat_gateways : {}
}

# AWS's own "Recommended Alarms" for AWS/NATGateway - detects the NAT gateway
# failing to allocate a source port for a new connection (too many concurrent
# connections to one popular destination).
resource "aws_cloudwatch_metric_alarm" "error_port_allocation" {
  for_each = local._error_port_allocation_targets

  alarm_name          = "${local._alarm_name_prefix[each.key]}-nat-error-port-allocation"
  alarm_description   = "NAT gateway ${each.key} could not allocate a source port for a new connection."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarms.error_port_allocation.evaluation_periods
  datapoints_to_alarm = var.alarms.error_port_allocation.datapoints_to_alarm
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = var.alarms.error_port_allocation.period_seconds
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[each.key].id
  }

  alarm_actions = var.alarms.error_port_allocation.alarm_actions
  ok_actions    = var.alarms.error_port_allocation.ok_actions

  tags = local.tagger_tags["nat-${each.key}"]
}

# AWS's own "Recommended Alarms" for AWS/NATGateway - detects the NAT gateway
# dropping packets (it processes up to 10M packets/sec; beyond that it drops).
resource "aws_cloudwatch_metric_alarm" "packets_drop" {
  for_each = local._packets_drop_targets

  alarm_name          = "${local._alarm_name_prefix[each.key]}-nat-packets-drop"
  alarm_description   = "NAT gateway ${each.key} is dropping packets."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarms.packets_drop.evaluation_periods
  datapoints_to_alarm = var.alarms.packets_drop.datapoints_to_alarm
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = var.alarms.packets_drop.period_seconds
  statistic           = "Sum"
  threshold           = var.alarms.packets_drop.threshold

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[each.key].id
  }

  alarm_actions = var.alarms.packets_drop.alarm_actions
  ok_actions    = var.alarms.packets_drop.ok_actions

  tags = local.tagger_tags["nat-${each.key}"]
}

# Not an AWS-recommended alarm - this module's own addition. Estimates
# bandwidth utilization against the NAT gateway's documented ceiling
# (5 Gbps baseline, auto-scales to bandwidth_limit_gbps) from
# BytesInFromSource + BytesInFromDestination, a CloudWatch-derived estimate,
# not AWS's internal bandwidth accounting.
resource "aws_cloudwatch_metric_alarm" "bandwidth_utilization" {
  for_each = local._bandwidth_targets

  alarm_name          = "${local._alarm_name_prefix[each.key]}-nat-bandwidth-utilization"
  alarm_description   = "NAT gateway ${each.key} estimated bandwidth utilization is above ${var.alarms.bandwidth_utilization.threshold_percent}% of its ${var.alarms.bandwidth_utilization.bandwidth_limit_gbps} Gbps ceiling."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarms.bandwidth_utilization.evaluation_periods
  datapoints_to_alarm = var.alarms.bandwidth_utilization.datapoints_to_alarm
  threshold           = var.alarms.bandwidth_utilization.threshold_percent

  metric_query {
    id          = "bytes_in_source"
    return_data = false
    metric {
      namespace   = "AWS/NATGateway"
      metric_name = "BytesInFromSource"
      period      = var.alarms.bandwidth_utilization.period_seconds
      stat        = "Sum"
      dimensions = {
        NatGatewayId = aws_nat_gateway.this[each.key].id
      }
    }
  }

  metric_query {
    id          = "bytes_in_dest"
    return_data = false
    metric {
      namespace   = "AWS/NATGateway"
      metric_name = "BytesInFromDestination"
      period      = var.alarms.bandwidth_utilization.period_seconds
      stat        = "Sum"
      dimensions = {
        NatGatewayId = aws_nat_gateway.this[each.key].id
      }
    }
  }

  metric_query {
    id          = "utilization_pct"
    label       = "Estimated bandwidth utilization (%)"
    return_data = true
    expression  = "(bytes_in_source + bytes_in_dest) * 8 / ${var.alarms.bandwidth_utilization.period_seconds} / (${var.alarms.bandwidth_utilization.bandwidth_limit_gbps} * 1000000000) * 100"
  }

  alarm_actions = var.alarms.bandwidth_utilization.alarm_actions
  ok_actions    = var.alarms.bandwidth_utilization.ok_actions

  tags = local.tagger_tags["nat-${each.key}"]
}

# Not an AWS-recommended alarm - this module's own addition. Projects a
# full-month data-processing cost from the same two Bytes* metrics as
# bandwidth_utilization, split by direction because AWS bills them
# differently: the NAT gateway's own per-GB fee applies to both directions,
# but AWS's separate "data transfer OUT to the internet" fee applies only
# to egress (BytesInFromSource - traffic the NAT received from VPC clients,
# bound for the internet) - AWS never charges for the ingress direction
# (BytesInFromDestination - responses coming back from the internet).
# Compared against a caller-supplied monthly budget (scaled down to
# whatever period this alarm actually evaluates over). This is a
# CloudWatch-derived estimate, not the authoritative AWS billing meter - it
# can differ from your actual bill.
resource "aws_cloudwatch_metric_alarm" "estimated_data_processing_cost" {
  for_each = local._cost_targets

  alarm_name          = "${local._alarm_name_prefix[each.key]}-nat-estimated-data-processing-cost"
  alarm_description   = "NAT gateway ${each.key} estimated data-processing cost is on pace to exceed its $${var.alarms.estimated_data_processing_cost.monthly_budget_usd}/month budget."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarms.estimated_data_processing_cost.evaluation_periods
  datapoints_to_alarm = var.alarms.estimated_data_processing_cost.datapoints_to_alarm
  threshold           = var.alarms.estimated_data_processing_cost.monthly_budget_usd * var.alarms.estimated_data_processing_cost.period_seconds / (30 * 24 * 3600)

  metric_query {
    id          = "egress_bytes"
    return_data = false
    metric {
      namespace   = "AWS/NATGateway"
      metric_name = "BytesInFromSource"
      period      = var.alarms.estimated_data_processing_cost.period_seconds
      stat        = "Sum"
      dimensions = {
        NatGatewayId = aws_nat_gateway.this[each.key].id
      }
    }
  }

  metric_query {
    id          = "ingress_bytes"
    return_data = false
    metric {
      namespace   = "AWS/NATGateway"
      metric_name = "BytesInFromDestination"
      period      = var.alarms.estimated_data_processing_cost.period_seconds
      stat        = "Sum"
      dimensions = {
        NatGatewayId = aws_nat_gateway.this[each.key].id
      }
    }
  }

  metric_query {
    id          = "estimated_cost_usd"
    label       = "Estimated data-processing + data-transfer-out cost for this period (USD)"
    return_data = true
    # A private NAT gateway never reaches the internet (VPC/on-prem only),
    # so the data-transfer-out term never applies to it regardless of what
    # the caller set - zeroed here per entry, not left for the caller to
    # remember for every private one.
    expression = "(egress_bytes + ingress_bytes) / 1073741824 * ${var.alarms.estimated_data_processing_cost.price_per_gb_processed} + egress_bytes / 1073741824 * ${each.value.connectivity_type == "public" ? var.alarms.estimated_data_processing_cost.price_per_gb_data_transfer_out : 0}"
  }

  alarm_actions = var.alarms.estimated_data_processing_cost.alarm_actions
  ok_actions    = var.alarms.estimated_data_processing_cost.ok_actions

  tags = local.tagger_tags["nat-${each.key}"]
}

locals {
  # Network topology fragment for composition with sibling modules via
  # provider::netutils::mermaid_merge() - see
  # https://github.com/rafalmasiarek/terraform-provider-netutils/blob/main/docs/topology-fragment-spec.md
  #
  # A private NAT gateway never reaches an IGW (it only routes between
  # VPCs/on-prem), so it never gets the nat -> igw edge below regardless of
  # topology_igw_id.
  topology_fragment = {
    entities = [
      for k, v in var.nat_gateways : {
        id     = aws_nat_gateway.this[k].id
        label  = k
        kind   = v.connectivity_type == "private" ? "nat-gateway-private" : "nat-gateway"
        parent = v.subnet_id
      }
    ]
    edges = var.topology_igw_id != null ? [
      for k, v in var.nat_gateways : {
        from  = aws_nat_gateway.this[k].id
        to    = var.topology_igw_id
        kind  = null
        label = null
      } if v.connectivity_type == "public"
    ] : []
  }
}
