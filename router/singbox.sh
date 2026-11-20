#!/bin/sh
# Side switch handler for GL.iNet firmware: /etc/rc.button/switch runs it with "on" or "off" when the
# switch moves, and at boot with its current position.

case "$1" in
  on)
    logger -t edge-gateway "switch on: starting sing-box"
    /etc/init.d/sing-box start
    ;;
  off)
    logger -t edge-gateway "switch off: stopping sing-box"
    /etc/init.d/sing-box stop
    ;;
esac
