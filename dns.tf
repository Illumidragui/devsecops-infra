# DNS records for the lab/demo subdomains on the k3s EC2 box, managed via Cloudflare
# (the zone's authoritative nameservers — Porkbun is only the domain registrar).
#
# apex (shengjunye.me) and www are NOT managed here — they're a Cloudflare Pages
# custom domain (see website/.github/workflows/deploy-cloudflare.yml, project
# "shengsite"), owned entirely by Cloudflare Pages as CNAME records. Don't add them
# as cloudflare_dns_record resources in this repo — Pages already manages that DNS,
# and Terraform trying to create an A record at the same name will 400 with
# "A CNAME record with that host already exists" (error 81054).
#
# kuberflow is un-proxied and points at the EIP; destroy-all.sh/.yml
# intentionally tears it down alongside a full teardown (see CLAUDE.md).
data "cloudflare_zone" "shengjunye" {
  filter = {
    name = "shengjunye.me"
  }
}

resource "cloudflare_dns_record" "kuberflow" {
  zone_id = data.cloudflare_zone.shengjunye.id
  name    = "kuberflow"
  type    = "A"
  content = aws_eip.k3s.public_ip
  ttl     = 600
  proxied = false
}
