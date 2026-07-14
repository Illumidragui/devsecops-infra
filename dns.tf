# DNS records for shengjunye.me, managed via Cloudflare (the zone's authoritative
# nameservers — Porkbun is only the domain registrar). apex/www are proxied through
# Cloudflare and — like the EIP — must never be destroyed alongside the EC2 instance.
# hello/kuberflow are un-proxied lab/demo subdomains; destroy-all.sh/.yml intentionally
# tears these two down alongside a full teardown (see CLAUDE.md invariants).
data "cloudflare_zone" "shengjunye" {
  filter = {
    name = "shengjunye.me"
  }
}

resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.shengjunye.id
  name    = "@"
  type    = "A"
  content = aws_eip.k3s.public_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "www" {
  zone_id = data.cloudflare_zone.shengjunye.id
  name    = "www"
  type    = "A"
  content = aws_eip.k3s.public_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "hello" {
  zone_id = data.cloudflare_zone.shengjunye.id
  name    = "hello"
  type    = "A"
  content = aws_eip.k3s.public_ip
  ttl     = 600
  proxied = false
}

resource "cloudflare_dns_record" "kuberflow" {
  zone_id = data.cloudflare_zone.shengjunye.id
  name    = "kuberflow"
  type    = "A"
  content = aws_eip.k3s.public_ip
  ttl     = 600
  proxied = false
}
