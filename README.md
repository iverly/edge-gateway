# edge-gateway

A self-hosted exit node for staying connected from networks that filter the internet: hotel
Wi-Fi, censored countries, captive networks. One container on a machine you trust (a home server,
an office Mac mini, a small VPS) turns it into a gateway your laptop and phone reach through
traffic that looks like ordinary HTTPS.

## Lanes

A node serves up to three lanes. Clients test them continuously and use the fastest one that
answers, so losing a lane costs a few seconds, not the connection.

| Lane       | Transport                                                    | Needs                           | Best for                                                |
| ---------- | ------------------------------------------------------------ | ------------------------------- | ------------------------------------------------------- |
| Reality    | VLESS + Reality, TCP                                         | one forwarded port              | web, APIs, everyday traffic                             |
| Hysteria2  | QUIC with salamander obfuscation, UDP, optional port hopping | one forwarded port (or a range) | calls, video, lossy links                               |
| Cloudflare | VLESS over WebSocket behind a Cloudflare tunnel              | a tunnel token, no open port    | a slow lane that is hard to block, to repair the others |

Reality answers anyone without the key with the real certificate of the site it impersonates, so
probing the port reveals nothing. Every node generates its own keys on first start and keeps them
in its data volume; nothing secret lives in the image or in this repository.

Several nodes combine into one client profile: a home node with open ports as the fast lane and
office nodes behind Cloudflare tunnels as the fallback, for instance.

## Run a node

```sh
mkdir edge-gateway && cd edge-gateway
curl -fsSLO https://raw.githubusercontent.com/iverly/edge-gateway/main/docker-compose.yml
curl -fsSL https://raw.githubusercontent.com/iverly/edge-gateway/main/.env.example -o .env
# edit .env: NODE_NAME, PUBLIC_HOST and the lanes to enable
docker compose up -d
```

`.env.example` documents every setting. `docker compose run --rm edge-gateway check` validates
them without serving.

## Connect

```sh
docker compose exec edge-gateway edge-gateway node > home.json     # this node's descriptor
docker compose run --rm -v "$PWD:/w" edge-gateway profile /w/home.json /w/office.json > profile.json
docker compose run --rm -v "$PWD:/w" edge-gateway links /w/home.json  # share links + QR codes
```

- **Descriptors** (`node`) hold the node's secrets: keep them private.
- **`profile.json`** imports into the sing-box apps (macOS, iOS, Android) or runs with the sing-box
  CLI on a travel router. Chinese domains and IPs go direct; everything else takes the fastest
  lane.
- **Share links** import into Shadowrocket, Hiddify or v2rayN.

Download the profile's rule sets once before travelling: the apps cache them.

## Travel router

`profile --router` builds a profile for sing-box on an OpenWrt travel router, covering every device
on its Wi-Fi. `router/install.sh` installs it on a GL.iNet router over SSH: the official sing-box
binary, a service, and the side switch as the VPN on/off control, also at boot. Its files are
listed for firmware upgrades that keep settings; running the installer again restores everything
after a reset.

```sh
docker compose run --rm -v "$PWD:/w" edge-gateway profile --router /w/home.json > router.json
router/install.sh root@192.168.8.1 router.json
```

## Dynamic DNS

A node at home whose public IP changes can keep its `PUBLIC_HOST` record up to date on
Cloudflare: set `DDNS_CF_API_TOKEN` and `DDNS_CF_ZONE_ID`, and the record follows the IP within
`DDNS_INTERVAL` seconds.

## Alerts

With `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`, a node watches its own lanes and the peers in
`WATCH_PEERS`, and sends a message each time one goes down or comes back.

## License

MIT
