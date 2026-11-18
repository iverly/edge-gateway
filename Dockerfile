ARG SING_BOX_VERSION=v1.14.4
ARG CLOUDFLARED_VERSION=2026.11.1

FROM ghcr.io/sagernet/sing-box:${SING_BOX_VERSION} AS sing-box
FROM cloudflare/cloudflared:${CLOUDFLARED_VERSION} AS cloudflared

FROM alpine:3.22
RUN apk add --no-cache bash ca-certificates curl iptables ip6tables jq libqrencode-tools openssl tzdata
COPY --from=sing-box /usr/local/bin/sing-box /usr/local/bin/sing-box
COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY rootfs/ /
RUN chmod 755 /usr/local/bin/edge-gateway /usr/local/bin/edge-watch /usr/local/bin/edge-ddns

ENV DATA_DIR=/data
VOLUME /data
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD ["edge-gateway", "health"]
ENTRYPOINT ["edge-gateway"]
CMD ["serve"]
