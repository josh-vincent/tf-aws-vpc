// Because we are reading in a YAML file, if we want to validate the variable
// values, we will need to pass in the rendered contents of the YAML file, otherwise
// the remote module won't be able to validate the values at runtime.

// Here we are just expanding out the YAML file in the event of multiple VPC's
locals {
  vpc = flatten([
  for fk, f in fileset("${path.module}/files/vpc", "*") :[
  for vpc_key, vpc in yamldecode(file("${path.module}/files/vpc/${f}")) : {
    vpc_key   = vpc_key
    vpc_value = vpc
  }]
  ])
  // now we would like to present the module with our VPC map in the format
  // of vpc_name => vpc
  vpc_map = {
  for vpc in local.vpc : vpc.vpc_key => vpc.vpc_value
  }
}


// Expand out the YAML file to capture all the security groups
locals {
  sg     = flatten([
  for fk, f in fileset("${path.module}/files/security_groups", "**/*{.yaml,.json}") : [
  for sg_key, sg in yamldecode(file("${path.module}/files/security_groups/${f}")) : {
    filename = trimsuffix(fk, ".yaml" )
    sg_key   = sg_key
    sg_value = sg
  }
  ]
  ])
  // now we would like to present the module with our security group map
  sg_map = {
  for sg in local.sg : "${sg.filename}.${sg.sg_key}" => sg.sg_value
  }
}


# ------------------------------------------------------------------------------
# Pass the local variables to the module
# ------------------------------------------------------------------------------
module "vpc_module" {
  source = "./modules/vpc"
  vpc_definition = local.vpc_map
  sg_definition = local.sg_map
  aws_tags = yamldecode(templatefile("files/tags/tags.yaml",{}))
}


