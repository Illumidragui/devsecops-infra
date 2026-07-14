# EIP lives outside module.ec2 so it survives terraform destroy -target=module.ec2.
# The association is re-created on each deploy and torn down with the instance.
resource "aws_eip" "k3s" {
  domain = "vpc"

  tags = {
    Name = "${local.project_name}-${local.environment}-eip"
  }
}

resource "aws_eip_association" "k3s" {
  count         = 1
  instance_id   = module.ec2.instance_id
  allocation_id = aws_eip.k3s.allocation_id

  depends_on = [module.ec2]
}
