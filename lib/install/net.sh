# shellcheck shell=bash
# step net (on demand): Tailscale with Tailscale SSH.

step_net() {
  say "Starting tailscaled"
  sudo systemctl enable --now tailscaled
  say "Joining your tailnet: open the link below and sign in"
  sudo tailscale up --ssh || die "tailscale up failed (see above); rerun: ultron install net"
  say "In https://login.tailscale.com/admin/dns turn on MagicDNS and HTTPS Certificates (phone alerts need both)"
  echo "  Note: Tailscale SSH's default policy also lets your own devices log in as root here; tighten the \"ssh\" rules in https://login.tailscale.com/admin/acls"
}
