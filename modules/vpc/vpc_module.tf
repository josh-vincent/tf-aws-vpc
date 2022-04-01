locals {
  // start by flattening the structure
  vpc = flatten([
  for vpc_key, vpc in var.vpc_definition : {
    network_key    = vpc_key
    vpc_cidr       = vpc.cidr
    enable_dns_hostnames = vpc.enable_dns_hostnames
    attach_to_tgw     = vpc.attach_to_tgw
    dhcp_options = vpc.dhcp_options
    enable_ipv6 = vpc.enable_ipv6
  }])

  // also flatten the subnet structure and correlate to the relevant VPC via vpc_key
  subnets = flatten([
  for vpc_key, vpc in var.vpc_definition : [
  for subnet_key, subnet in vpc.subnets : {
    network_key = vpc_key
    subnet_key  = subnet_key
    subnet_cidr = subnet.cidr
    attach_to_tgw  = vpc.attach_to_tgw

  }]])

  // var.sg_definition contains a k-v pair per security group, per rule.. this would
  // mean that we'd have a security group per rule (which we don't want). Here we
  // are using the filename as the name of the security group and correlating it
  // with each VPC; the distinct() function ensures we remove all duplicates. For e.g.
  // if we have 2 VPC's and 3 YAML files containing security group rules, we end up
  // with 3 security groups in each VPC. We create vpc_rules as an easy way to create
  // the empty security groups.
  vpc_rules = distinct(flatten([
  for sg_key, sg in var.sg_definition : [
  for vpc_key, vpc in local.vpc : {
    filename   = element(split(".", sg_key),0)
    network_key = vpc.network_key
  }]]))

  // flatten the structure of all the rules
  rules = flatten([
  for sg_key, sg in var.sg_definition : {
    filename = element(split(".", sg_key),0)
    rule_key = element(split(".", sg_key),1)
    rule = sg
  }])

  // construct an object of the ingress and egress rules
  _ingress  = {for k, v in local.rules : "${v.filename}.${v.rule_key}" => v.rule if(v.rule.direction == "ingress") }
  _egress   = {for k, v in local.rules : "${v.filename}.${v.rule_key}" => v.rule if(v.rule.direction == "egress") }

  // correlate all ingress rules with the VPC
  ingress_rules = flatten([
  for vpc_key, vpc in local.vpc : [
  for rule_key, rule in local._ingress : {
    network_key = vpc.network_key
    filename = element(split(".", rule_key),0)
    rule_key = element(split(".", rule_key),1)
    rule = rule
  }]])

  // correlate all egress rules with the VPC
  egress_rules = flatten([
  for vpc_key, vpc in local.vpc : [
  for rule_key, rule in local._egress : {
    network_key = vpc.network_key
    filename = element(split(".", rule_key),0)
    rule_key = element(split(".", rule_key),1)
    rule = rule
  }]])
}

# ------------------------------------------------------------------------------
# Create the VPC - specify the name as the key
# ------------------------------------------------------------------------------
resource "aws_vpc" "v" {
  for_each = {
  for vpc in local.vpc : vpc.network_key => vpc
  }
  cidr_block        = each.value.vpc_cidr
  enable_dns_hostnames = each.value.enable_dns_hostnames
  assign_generated_ipv6_cidr_block = each.value.enable_ipv6
  tags = merge(
  var.aws_tags,
  {
    Name        = each.value.network_key,
    environment = element(split("-", each.value.network_key), 2)
  }, )
}
# ------------------------------------------------------------------------------
# Create the security groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "security_group" {
  for_each = {
  for rule in local.vpc_rules : "${rule.filename}.${rule.network_key}" => rule
  }
  vpc_id = aws_vpc.v[each.value.network_key].id
  name = each.value.filename
  tags = merge(
  var.aws_tags,
  {
    Name = each.value.filename
  }, )
}

# ------------------------------------------------------------------------------
# Create the egress rules
# ------------------------------------------------------------------------------
resource "aws_security_group_rule" "egress_rules" {
  for_each = {
  for rule in local.egress_rules : "${rule.filename}.${rule.network_key}.${rule.rule_key}" => rule
  }

  type              = "egress"
  from_port         = each.value.rule.from_port
  to_port           = each.value.rule.to_port
  protocol          = each.value.rule.protocol
  cidr_blocks       = each.value.rule.cidr_blocks
  description       = each.value.rule.description
  security_group_id = aws_security_group.security_group["${each.value.filename}.${each.value.network_key}"].id
}

# ------------------------------------------------------------------------------
# Create the ingress rules
# ------------------------------------------------------------------------------
resource "aws_security_group_rule" "ingress_rules" {
  for_each = {
  for rule in local.ingress_rules : "${rule.filename}.${rule.network_key}.${rule.rule_key}" => rule
  }

  type              = "ingress"
  from_port         = each.value.rule.from_port
  to_port           = each.value.rule.to_port
  protocol          = each.value.rule.protocol
  cidr_blocks       = each.value.rule.cidr_blocks
  description       = each.value.rule.description
  security_group_id = aws_security_group.security_group["${each.value.filename}.${each.value.network_key}"].id
}

# ------------------------------------------------------------------------------
# Create the DHCP option sets
# ------------------------------------------------------------------------------
resource "aws_vpc_dhcp_options" "dhcp_options" {
  for_each = {
  for vpc in local.vpc : vpc.network_key => vpc if vpc.dhcp_options != null
  }
  domain_name = each.value.dhcp_options["domain_name"]
  domain_name_servers  = each.value.dhcp_options["domain_name_servers"]

  tags = merge(
  var.aws_tags,
  {
    Name        = format("%s%s", each.value.dhcp_options["domain_name"], "-dhcp-option-set")
  }, )
}

# ------------------------------------------------------------------------------
# Associate the option set with the relevant VPC's
# ------------------------------------------------------------------------------
resource "aws_vpc_dhcp_options_association" "dhcp_option_association" {
  for_each = {
  for vpc in local.vpc : vpc.network_key => vpc if vpc.dhcp_options != null
  }
  vpc_id          = aws_vpc.v[each.value.network_key].id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp_options[each.value.network_key].id

}

# ------------------------------------------------------------------------------
# Create all the subnets
# ------------------------------------------------------------------------------
resource "aws_subnet" "s" {

  for_each = {
  for subnet in local.subnets : "${subnet.network_key}.${subnet.subnet_key}" => subnet
  }
  vpc_id            = aws_vpc.v[each.value.network_key].id
  cidr_block        = each.value.subnet_cidr
  availability_zone = format("%s%s", "ap-southeast-", regex("(\\d\\D)", each.value.subnet_key)[0])
  tags = merge(
  var.aws_tags,
  {
    Name        = each.value.subnet_key,
    environment = element(split("-", each.value.network_key), 2)
  }, )
}

# ------------------------------------------------------------------------------
# Create the VPC route tables; there is only a single private route table per VPC
# ------------------------------------------------------------------------------
resource "aws_route_table" "vpc-rt" {
  for_each = {
  for vpc in local.vpc : vpc.network_key => vpc
  }
  vpc_id   = aws_vpc.v[each.value.network_key].id
  tags = merge(
  var.aws_tags,
  {
    Name        = "${each.value.network_key}-rt",
    environment = element(split("-", each.value.network_key), 2)
  }, )
}