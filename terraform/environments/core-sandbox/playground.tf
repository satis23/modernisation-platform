# Sharing
provider "aws" {
  alias  = "core-vpc-production"
  region = "eu-west-2"

  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids["core-vpc-production"]}:role/ModernisationPlatformAccess"
  }
}

# Share the core VPC with this account
resource "aws_ram_principal_association" "vpc-production-shared" {
  provider = aws.core-vpc-production

  principal          = data.aws_caller_identity.current.account_id
  resource_share_arn = data.aws_ram_resource_share.vpc-production-shared.arn
}

data "aws_ram_resource_share" "vpc-production-shared" {
  provider       = aws.core-vpc-production
  name           = "core-vpc-production-to-hmpps"
  resource_owner = "SELF"
}

# EC2

# Lookup shared VPC details
locals {
  shared_vpc_cidr = "10.232.0.0/18"
}

data "aws_vpc" "shared-from-core-vpc-production" {
  cidr_block = local.shared_vpc_cidr
}

# Lookup shared VPC subnets
data "aws_subnet" "shared-from-core-vpc-production" {
  cidr_block = "10.232.24.0/22"
}

output "test" {
  value = data.aws_subnet.shared-from-core-vpc-production
}

# Create instance in the shared VPC
resource "aws_instance" "test" {
  ami           = "ami-08b993f76f42c3e2f" # AWS Linux 2 AMI
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnet.shared-from-core-vpc-production.id
  key_name      = aws_key_pair.bastion_key.key_name

  vpc_security_group_ids = [
    aws_security_group.default.id
  ]

  tags = merge(
    local.tags,
    {
      Name = "playground.tf"
    }
  )
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "deployer-key"
  public_key = "[redacted]" # I've removed this and added a lifecycle {} block below which will ignore changes. Feel free to remove the lifecycle block and update the public key as required, but it saved me committing my key to GitHub.

  tags = merge(
    local.tags,
    {
      Name = "playground.tf"
    }
  )

  lifecycle {
    ignore_changes = [public_key]
  }
}

# SG
resource "aws_security_group" "default" {
  name   = "allow_ssh"
  vpc_id = data.aws_vpc.shared-from-core-vpc-production.id

  tags = merge(
    local.tags,
    {
      Name = "playground.tf"
    }
  )
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.shared_vpc_cidr]       # from core-vpc-production
  security_group_id = aws_security_group.default.id # from core-network-services
}