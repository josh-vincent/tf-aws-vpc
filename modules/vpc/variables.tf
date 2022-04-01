variable "aws_tags" {
  description = <<EOF
  This object represents the tags that are to be applied to applicable resources.

      `application (Required)` - Specifies the application type, ex. Infrastructure.
     `environment (Required)` - Specifies the environment.
   EOF
  type = object({
    application   = string
    environment   = string
    managed-by    = string
  })

  // basic validation
  validation {
    condition = length(var.aws_tags.application) > -1
    error_message = "The application tag must be set."
  }
  validation {
    condition = length(var.aws_tags.environment) > -1
    error_message = "The environment tag must be set."
  }
  validation {
    condition = contains(["ClickOps", "Terraform", "CloudFormation"], var.aws_tags.managed-by)
    error_message = "Supported tags for managed-by are: ClickOps, Terraform, CloudFormation."
  }

  // validate environment is either prod, non-prod, qa, dev, test, sandbox
  validation {
    condition = (can(regex("(prod|non-prod|qa|dev|test|sandbox)", lower(var.aws_tags.environment))))
    error_message = "The environment tag can only be set to one of the following: [prod,non-prod,qa,dev,test,sandbox]."
  }

  // validate managed-by is set to Terraform
  validation {
    condition = (var.aws_tags.managed-by == "Terraform")
    error_message = "The managed-by tag can only be set to the following: [Terraform]."
  }
}

variable "vpc_definition" {
  description = <<EOF
  A valid `.yaml` file containing the following key-value pairs is required. The key for the `.yaml` file will be used as the VPC name.

      - `dhcp_options (Required)` - Specifies the DHCP option set for the VPC. If you wish to use the default Amazon provided options, set the domain_name to ap-southeast-2.compute.internal and domain_name_servers to ["AmazonProvidedDNS"].
      - `enable_dns_hostnames (Required)` - Specifies whether to enable DNS hostname support for the VPC. If you wish to use privateLink, this will need to be `true`. See https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html for further info. Default: false.
      - `enable_ipv6 (Required)` - Specifies whether to enable ipv6 auto generated in the VPC. Default: false.
      - `attach_to_tgw (Required)` - Specifies whether you'd like to attach the VPC to the transit gateway. Default: false.
      - `cidr (Required)` - Specifies the base CIDR for the VPC. The CIDR block size must be between /16 and /28.
      - `subnets (Required)` - key-value pairs of all the subnet and CIDR pairs you'd like created. The CIDR range must be within the VPC CIDR range.
        - `subnet_key (Required)` - Specifies the name of the subnet as per the naming convention.
          - `cidr (Required)` - Specifies the CIDR range for the subnet.
  EOF
  type = map(object({
    dhcp_options = object({
      domain_name = string,
      domain_name_servers = list(string)
    })
    enable_dns_hostnames = bool
    enable_ipv6 = bool
    attach_to_tgw = bool
    cidr            = string
    subnets = map(object({
      cidr = string
    }))
  }))

  validation {
    condition = alltrue([
    for v in var.vpc_definition : can(regex("ap-southeast-2.compute.internal", lower(v.dhcp_options.domain_name)))
    ])
    error_message = "The domain name can only be of the following type: [ap-southeast-2.compute.internal] ."
  }
}

variable "sg_definition" {
  description = <<EOF
  A valid `.yaml` file containing the following key-value pairs is required. The filename of the `.yaml` file will be used as the Security group name.

      `direction (Required)`  - Specifies the direction for the security group rule, either "ingress" or "egress".
      `cidr_blocks (Required)` - Specifies the CIDR blocks you wish the rule to apply to. **Note: a rule is created for each entry in the CIDR block, per rule.**
      `description (Required)` - Specifies a description for the security group.
      `from_port (Required)` - Specifies the start port range.
      `to_port (Required)` - Specifies the end port range.
      `protocol (Required)` - Specifies the protocol, either TCP, UDP or -1 (for ICMP).
  EOF
  type = map(object({
    direction = string
    cidr_blocks = list(string)
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
  }))
  #
  // ensure only egress or ingress are specified for the direction
  validation {
    condition = alltrue([
    for v in var.sg_definition : can(regex("(egress|ingress)", lower(v.direction)))
    ])
    error_message = "The security group direction can only be of the following type: [egress, ingress] ."
  }
}