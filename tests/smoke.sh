#!/usr/bin/env bash
# End-to-end check of an image: a node serving the Reality and Hysteria2 lanes, a client built from
# its descriptor reaching the internet through each lane, and the Cloudflare lane's config.
# Usage: tests/smoke.sh [image]   (default: builds edge-gateway:test from the repository)
set -euo pipefail

IMAGE=${1:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NET=edge-gateway-smoke
SERVER=edge-gateway-smoke-server
WEB=edge-gateway-smoke-web
PORT=18443
WORK=$(mktemp -d)

cleanup() {
  docker rm -f "$SERVER" "$WEB" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$SERVER" 2>&1 | tail -20 >&2 || true
  exit 1
}

if [ -z "$IMAGE" ]; then
  IMAGE=edge-gateway:test
  docker build -q -t "$IMAGE" "$ROOT" >/dev/null
fi

echo "== refuses to start without a lane"
if docker run --rm "$IMAGE" check >/dev/null 2>&1; then fail "started with no lane"; fi

echo "== renders the Cloudflare lane"
docker run --rm -e CF_TUNNEL_TOKEN=dummy -e CF_HOSTNAME=t.example.com "$IMAGE" check >/dev/null ||
  fail "cloudflare lane config"

echo "== serves Reality and Hysteria2"
docker network create "$NET" >/dev/null
docker run -d --name "$SERVER" --network "$NET" \
  -e NODE_NAME=smoke -e PUBLIC_HOST="$SERVER" -e REALITY_PORT=$PORT -e HY2_PORT=$PORT \
  "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$SERVER")" = healthy ] && break
  sleep 1
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$SERVER")" = healthy ] || fail "server not healthy"

docker exec "$SERVER" edge-gateway node >"$WORK/node.json"
jq -e '.reality and .hy2 and (.cf == null)' "$WORK/node.json" >/dev/null || fail "node descriptor"
docker exec -e REALITY_PUBLIC_PORT=443 -e HY2_PUBLIC_PORT=8443 "$SERVER" edge-gateway node |
  jq -e '.reality.port == 443 and .hy2.port == 8443' >/dev/null || fail "public ports in descriptor"

echo "== builds a valid client profile"
docker run --rm -v "$WORK:/w" "$IMAGE" profile /w/node.json >"$WORK/profile.json"
docker run --rm -v "$WORK:/w" --entrypoint sing-box "$IMAGE" check -c /w/profile.json ||
  fail "client profile rejected by sing-box"

echo "== builds a valid router profile"
docker run --rm -v "$WORK:/w" "$IMAGE" profile --router /w/node.json >"$WORK/router.json"
jq -e '.inbounds[0].interface_name == "sbtun" and (.inbounds[0].auto_redirect | not)
  and (.inbounds[1].tag == "dns-in" and .inbounds[1].listen_port == 5335)
  and .route.rules[0] == {inbound: "dns-in", action: "hijack-dns"}' "$WORK/router.json" >/dev/null ||
  fail "router profile shape"
jq -e '.inbounds | length == 1' "$WORK/profile.json" >/dev/null || fail "app profile gained router inbounds"
docker run --rm -v "$WORK:/w" --entrypoint sing-box "$IMAGE" check -c /w/router.json ||
  fail "router profile rejected by sing-box"

echo "== prints one share link per lane"
docker run --rm -e QR=0 -v "$WORK:/w" "$IMAGE" links /w/node.json >"$WORK/links.txt" ||
  fail "share links exit code"
[ "$(wc -l <"$WORK/links.txt" | tr -d ' ')" = 2 ] || fail "share links count"

# A web server on the node's private network stands for its LAN.
docker run -d --name "$WEB" --network "$NET" nginx:alpine >/dev/null

for lane in reality hy2; do
  echo "== reaches the internet through $lane"
  jq --arg tag "smoke-$lane" '{
    log: {level: "error"},
    inbounds: [{type: "mixed", listen: "127.0.0.1", listen_port: 2080}],
    outbounds: [.outbounds[] | select(.tag == $tag)]
  }' "$WORK/profile.json" >"$WORK/$lane.json"
  docker run --rm --network "$NET" -v "$WORK:/w" --entrypoint sh "$IMAGE" -c "
    sing-box run -c /w/$lane.json & sleep 2
    curl -fsS -o /dev/null --max-time 15 -x socks5h://127.0.0.1:2080 https://www.gstatic.com/generate_204
  " || fail "$lane lane"
  echo "== refuses the node's private network through $lane"
  if docker run --rm --network "$NET" -v "$WORK:/w" --entrypoint sh "$IMAGE" -c "
    sing-box run -c /w/$lane.json & sleep 2
    curl -fsS -o /dev/null --max-time 10 -x socks5h://127.0.0.1:2080 http://$WEB/
  " >/dev/null 2>&1; then fail "$lane lane reached a private address"; fi
done

echo "== reaches the node's private network with ALLOW_PRIVATE=1"
docker rm -f "$SERVER" >/dev/null
docker run -d --name "$SERVER" --network "$NET" \
  -e NODE_NAME=smoke -e PUBLIC_HOST="$SERVER" -e REALITY_PORT=$PORT -e ALLOW_PRIVATE=1 \
  "$IMAGE" >/dev/null
sleep 4
docker exec "$SERVER" edge-gateway node >"$WORK/node2.json"
docker run --rm -v "$WORK:/w" "$IMAGE" profile /w/node2.json |
  jq '{log: {level: "error"}, inbounds: [{type: "mixed", listen: "127.0.0.1", listen_port: 2080}],
       outbounds: [.outbounds[] | select(.tag == "smoke-reality")]}' >"$WORK/open.json"
docker run --rm --network "$NET" -v "$WORK:/w" --entrypoint sh "$IMAGE" -c "
  sing-box run -c /w/open.json & sleep 2
  curl -fsS -o /dev/null --max-time 10 -x socks5h://127.0.0.1:2080 http://$WEB/
" || fail "ALLOW_PRIVATE=1 did not reach the private network"

echo "OK"
