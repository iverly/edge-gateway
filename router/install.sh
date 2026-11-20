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

jq -e '.inbounds[0].auto_redirect == true' "$PROFILE" >/dev/null ||
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

echo "== downloading sing-box $VERSION linux-$arch"
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v$VERSION/sing-box-$VERSION-linux-$arch.tar.gz" |
  tar -xz -C "$WORK"

echo "== copying files"
ssh "$TARGET" 'mkdir -p /etc/sing-box/bin && chmod 700 /etc/sing-box'
scp -q "$WORK/sing-box-$VERSION-linux-$arch/sing-box" "$TARGET:/etc/sing-box/bin/sing-box.new"
scp -q "$PROFILE" "$TARGET:/etc/sing-box/config.json.new"
scp -q "$HERE/sing-box.init" "$TARGET:/etc/init.d/sing-box"
scp -q "$HERE/singbox.sh" "$TARGET:/etc/gl-switch.d/singbox.sh"

ssh "$TARGET" 'sh -s' <<'REMOTE'
set -eu
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

for path in /etc/sing-box/ /etc/init.d/sing-box /etc/gl-switch.d/singbox.sh; do
  grep -qxF "$path" /etc/sysupgrade.conf || echo "$path" >>/etc/sysupgrade.conf
done

. /lib/functions/gl_util.sh
position=$(get_switch_button_status)
echo "switch position: $position"
/etc/gl-switch.d/singbox.sh "$position"
REMOTE
echo "== done"
