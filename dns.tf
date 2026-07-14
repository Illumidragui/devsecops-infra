# DNS records for shengjunye.me, managed via Porkbun. These point at the persistent
# aws_eip.k3s and — like the EIP — must never be destroyed alongside the EC2 instance.
resource "porkbun_dns_record" "apex" {
  domain    = "shengjunye.me"
  subdomain = ""
  type      = "A"
  content   = aws_eip.k3s.public_ip
  ttl       = 600
}

resource "porkbun_dns_record" "www" {
  domain    = "shengjunye.me"
  subdomain = "www"
  type      = "A"
  content   = aws_eip.k3s.public_ip
  ttl       = 600
}

resource "porkbun_dns_record" "hello" {
  domain    = "shengjunye.me"
  subdomain = "hello"
  type      = "A"
  content   = aws_eip.k3s.public_ip
  ttl       = 600
}
