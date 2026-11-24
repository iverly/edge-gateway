#!/usr/bin/env bash
# Installs or updates sing-box and a router profile on a GL.iNet travel router over SSH, wires the
# side switch to it and lists every file in /etc/sysupgrade.conf so a firmware upgrade that keeps
# settings keeps them too. Safe to run again after a reset or an upgrade without kept settings.
# Usage: router/install.sh <ssh-target> <router-profile.json> [sing-box-version]
set -euo pipefail

TARGET=${1:?usage: install.sh <ssh-target> <router-profile.json> [sing-box-version]}
PROFILE=${2:?usage: install.sh <ssh-target> <router-profile.json> [sing-box-version]}
VERSION=${3:-1.14.4}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

jq -e '.inbounds[0].interface_name == "sbtun"' "$PROFILE" >/dev/null ||
  {
    echo "$PROFILE is not a router profile (edge-gateway profile --router)" >&2
    exit 1
  }

case "$(ssh "$TARGET" uname -m)" in
  aarch64) arch=arm64 ;;
  x86_64) arch=amd64 ;;
  armv7l) arch=armv7 ;;
  mips*) arch=mipsle ;;
  *)
    echo "unsupported router architecture" >&2
    exit 1
    ;;
esac

# OpenWrt links against musl: the default Linux build does not start there.
libc=""
if ssh "$TARGET" 'ls /lib/ld-musl-* >/dev/null 2>&1'; then libc=-musl; fi
build="sing-box-$VERSION-linux-$arch$libc"

echo "== downloading $build"
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v$VERSION/$build.tar.gz" |
  tar -xz -C "$WORK"

# OpenWrt's dropbear has no SFTP server, which scp needs by default: copy through ssh instead.
put() {
  # The remote path is meant to expand here, on the client.
  # shellcheck disable=SC2029
  ssh "$TARGET" "cat >'$2'" <"$1"
}

echo "== copying files"
ssh "$TARGET" 'mkdir -p /etc/sing-box/bin && chmod 700 /etc/sing-box'
put "$WORK/$build/sing-box" /etc/sing-box/bin/sing-box.new
put "$PROFILE" /etc/sing-box/config.json.new
put "$HERE/sing-box.init" /etc/init.d/sing-box
put "$HERE/singbox.sh" /etc/gl-switch.d/singbox.sh

# No set -u on the router: OpenWrt's own shell functions read unset variables.
ssh "$TARGET" 'sh -s' <<'REMOTE'
set -e
cd /etc/sing-box
chmod 755 bin/sing-box.new /etc/init.d/sing-box /etc/gl-switch.d/singbox.sh
chmod 600 config.json.new
bin/sing-box.new check -c config.json.new
mv bin/sing-box.new bin/sing-box
mv config.json.new config.json
bin/sing-box version | head -1

/etc/init.d/sing-box disable 2>/dev/null || true
uci set switch-button.@main[0].func=singbox
uci commit switch-button

# The TUN is a firewall zone of its own that the LAN may forward to; without it fw4 drops the
# devices' traffic on its way into sing-box.
if ! uci -q get firewall.edgegw >/dev/null; then
  uci set firewall.edgegw=zone
  uci set firewall.edgegw.name=edgegw
  uci add_list firewall.edgegw.device=sbtun
  uci set firewall.edgegw.input=ACCEPT
  uci set firewall.edgegw.output=ACCEPT
  uci set firewall.edgegw.forward=ACCEPT
  uci set firewall.edgegw_lan=forwarding
  uci set firewall.edgegw_lan.src=lan
  uci set firewall.edgegw_lan.dest=edgegw
  uci commit firewall
  /etc/init.d/firewall reload >/dev/null 2>&1
fi

# GL.iNet's encrypted DNS imposes its own upstream on dnsmasq and resolves outside the tunnel.
dns_mode=$(uci -q get gl-dns-v2.@dns[0].mode || echo auto)
[ "$dns_mode" = auto ] ||
  echo "warning: GL.iNet DNS mode is '$dns_mode'; set NETWORK > DNS > Mode to Automatic"

for path in /etc/sing-box/ /etc/init.d/sing-box /etc/gl-switch.d/singbox.sh; do
  grep -qxF "$path" /etc/sysupgrade.conf || echo "$path" >>/etc/sysupgrade.conf
done

. /lib/functions/gl_util.sh
position=$(get_switch_button_status)
echo "switch position: $position"
# A running sing-box keeps its old binary and profile until it restarts.
if [ "$position" = on ]; then
  /etc/init.d/sing-box restart
else
  /etc/gl-switch.d/singbox.sh off
fi
REMOTE
echo "== done"
