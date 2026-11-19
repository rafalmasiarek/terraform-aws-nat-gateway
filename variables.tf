variable "nat_gateways" {
  description = "One aws_nat_gateway per entry, typically keyed by AZ (e.g. \"a\", \"b\"), one per AZ for HA egress. connectivity_type = \"public\" (default) gets its own aws_eip unless allocation_id is set; \"private\" gets neither (no internet access, routes between VPCs/on-prem only - see AWS's private NAT gateway docs)."
  type = map(object({
    subnet_id                = string
    connectivity_type        = optional(string, "public") # "public" | "private"
    allocation_id            = optional(string)           # bring your own EIP; ignored for "private"
    secondary_allocation_ids = optional(list(string), []) # extra EIPs for automatic port scaling; "public" only
    private_ip               = optional(string)           # "private" only - fixed private IP instead of an auto-assigned one
  }))

  validation {
    condition     = alltrue([for k, v in var.nat_gateways : contains(["public", "private"], v.connectivity_type)])
    error_message = "nat_gateways[].connectivity_type must be \"public\" or \"private\"."
  }
  validation {
    condition     = alltrue([for k, v in var.nat_gateways : v.connectivity_type == "public" || v.allocation_id == null])
    error_message = "nat_gateways[].allocation_id only applies to connectivity_type = \"public\" - a private NAT gateway has no Elastic IP."
  }
  validation {
    condition     = alltrue([for k, v in var.nat_gateways : v.connectivity_type == "public" || length(v.secondary_allocation_ids) == 0])
    error_message = "nat_gateways[].secondary_allocation_ids only applies to connectivity_type = \"public\"."
  }
  validation {
    condition     = alltrue([for k, v in var.nat_gateways : v.connectivity_type == "private" || v.private_ip == null])
    error_message = "nat_gateways[].private_ip only applies to connectivity_type = \"private\"."
  }
}

variable "topology_igw_id" {
  description = "Internet Gateway id, for the topology_fragment diagram only - a NAT gateway's own egress to the internet is automatic once an IGW exists in the VPC (no route table entry needed), so this module has no other reason to need it. Omit to leave the nat -> igw edge undrawn. Only applies to connectivity_type = \"public\" entries."
  type        = string
  default     = null
}

variable "price_per_hour" {
  description = "Estimated on-demand hourly price per NAT gateway, used only for the estimated_hourly_cost output - varies by region and contract (EDP/PPA), this module never looks it up itself. Leave null to skip the output."
  type        = number
  default     = null
}

variable "alarms" {
  description = <<-EOT
    CloudWatch alarms for every NAT gateway this module creates. Each key is independently
    toggled via its own `enabled`. error_port_allocation and packets_drop mirror AWS's own
    "Recommended Alarms" for AWS/NATGateway (see
    https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html).
    bandwidth_utilization and estimated_data_processing_cost are this module's own addition,
    built from the same BytesInFromSource/BytesInFromDestination metrics - they estimate
    usage from CloudWatch data, which is not the authoritative AWS billing meter and can
    differ from your actual bill.
  EOT
  type = object({
    error_port_allocation = optional(object({
      enabled             = optional(bool, true)
      period_seconds      = optional(number, 60)
      evaluation_periods  = optional(number, 15)
      datapoints_to_alarm = optional(number, 15)
      alarm_actions       = optional(list(string), [])
      ok_actions          = optional(list(string), [])
    }), {})

    packets_drop = optional(object({
      enabled             = optional(bool, false) # off by default - no safe universal threshold to default to, see the validation below
      threshold           = optional(number)      # no safe universal default - AWS: derive from your own traffic history (~0.01% of total traffic)
      period_seconds      = optional(number, 60)
      evaluation_periods  = optional(number, 5)
      datapoints_to_alarm = optional(number, 5)
      alarm_actions       = optional(list(string), [])
      ok_actions          = optional(list(string), [])
    }), {})

    bandwidth_utilization = optional(object({
      enabled              = optional(bool, false)
      threshold_percent    = optional(number, 80)
      bandwidth_limit_gbps = optional(number, 100) # AWS's current documented per-NAT-gateway ceiling - override if AWS changes it
      period_seconds       = optional(number, 300)
      evaluation_periods   = optional(number, 3)
      datapoints_to_alarm  = optional(number, 3)
      alarm_actions        = optional(list(string), [])
      ok_actions           = optional(list(string), [])
    }), {})

    estimated_data_processing_cost = optional(object({
      enabled = optional(bool, false)
      # NAT gateway's own per-GB fee - applies to all data it processes,
      # both directions. No safe universal default - varies by region/contract.
      price_per_gb_processed = optional(number)
      # Standard AWS "data transfer OUT to the internet" fee - applies only
      # to the egress direction (traffic AWS sends to the internet); AWS
      # never charges for the inbound/ingress direction. Defaults to 0 (not
      # modeled) rather than requiring it, since some callers only want the
      # NAT processing fee estimated.
      price_per_gb_data_transfer_out = optional(number, 0)
      monthly_budget_usd             = optional(number) # no safe universal default - your own budget
      period_seconds                 = optional(number, 3600)
      evaluation_periods             = optional(number, 1)
      datapoints_to_alarm            = optional(number, 1)
      alarm_actions                  = optional(list(string), [])
      ok_actions                     = optional(list(string), [])
    }), {})
  })
  default = {}

  validation {
    condition     = !var.alarms.packets_drop.enabled || var.alarms.packets_drop.threshold != null
    error_message = "alarms.packets_drop.threshold must be set when alarms.packets_drop.enabled is true - AWS has no universal safe default for it."
  }
  validation {
    condition     = !var.alarms.estimated_data_processing_cost.enabled || (var.alarms.estimated_data_processing_cost.price_per_gb_processed != null && var.alarms.estimated_data_processing_cost.monthly_budget_usd != null)
    error_message = "alarms.estimated_data_processing_cost requires both price_per_gb_processed and monthly_budget_usd when enabled."
  }
}
