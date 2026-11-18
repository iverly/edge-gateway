# edge-gateway

A Docker image that turns a machine into an exit node with up to three lanes (Reality over TCP,
Hysteria2 over UDP, VLESS over WebSocket behind a Cloudflare tunnel), plus the commands that build
client profiles from the nodes. Bash on Alpine, sing-box and cloudflared copied from their official
images.

## Layout

| Path                                 | What                                                            |
| ------------------------------------ | --------------------------------------------------------------- |
| `rootfs/usr/local/bin/edge-gateway`  | entrypoint: secrets, server config, serve, node, profile, links |
| `rootfs/usr/local/bin/edge-ddns`     | keeps the Cloudflare A record of `PUBLIC_HOST` on the public IP |
| `rootfs/usr/local/bin/edge-watch`    | Telegram alerts on lane and peer state changes                  |
| `Dockerfile`                         | the image; sing-box and cloudflared versions are build args     |
| `docker-compose.yml`, `.env.example` | how a node runs; `.env.example` documents every setting         |
| `tests/smoke.sh`                     | end-to-end test of an image                                     |

## Rules

- Configs are built with `jq`, never by string substitution: values reach JSON escaped.
- Secrets are generated at first start into the data volume. Nothing secret in the image, the
  repository, logs or test output.
- A client profile must pass `sing-box check` of the bundled sing-box version.
- Shell: bash, `set -euo pipefail`, formatted with `shfmt -i 2 -ci`, clean under `shellcheck`.
- Comments say why, about the code as it is now: no history, no references to issues or plans.
- English everywhere.

## Checks

`tests/smoke.sh` builds the image and checks every lane end to end; run it before pushing. The
pre-commit hook formats and lints staged files.

## Git

- Conventional commits, enforced by commitlint: `type(scope): subject`, scope mandatory, from the
  list in `commitlint.config.mjs`. Subject in English, imperative, lowercase, no trailing period.
- One concern per commit; the body says why.
- `main` has a linear history (rebase merges only). Never force-push `main`.
- Never push, tag or open a pull request without an explicit OK given at that moment.
- Never mention Claude or any AI in commits, pull requests or code.
- `docs/superpowers/` and `.superpowers/` stay local.
