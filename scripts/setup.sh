#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup.sh - creates the folder structure this docker-compose.yml expects.
# Run this ONCE, from the same folder as docker-compose.yml, before
# `docker compose up -d`.
#
# NOTE: this script now lives in a subfolder. docker-compose.yml and .env
# are expected one directory up (ENV_DIR below).
#
# Usage:
#   chmod +x setup.sh
#   sudo ./setup.sh
#
# Needs sudo because /srv is owned by root. The script hands the folders
# back to your user afterward so containers (running as PUID/PGID 1000)
# can actually write to them.
# ---------------------------------------------------------------------------
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run this with sudo: sudo ./setup.sh"
  exit 1
fi

# The user who ran sudo (so we can hand folder ownership back to them)
REAL_USER="${SUDO_USER:-$USER}"

# Change these two if you're using different paths (must match your .env)
APPDATA="/srv/appdata"
MEDIA="/srv/media"

# Where docker-compose.yml / .env live, relative to this script's location
ENV_DIR="$(dirname "$0")/.."

echo "Creating appdata folders under $APPDATA ..."
mkdir -p \
  "$APPDATA/traefik" \
  "$APPDATA/traefik/dynamic" \
  "$APPDATA/portainer" \
  "$APPDATA/pihole/etc-pihole" \
  "$APPDATA/pihole/etc-dnsmasq.d" \
  "$APPDATA/plex" \
  "$APPDATA/qbittorrent" \
  "$APPDATA/stirlingpdf/trainingData" \
  "$APPDATA/stirlingpdf/config" \
  "$APPDATA/stirlingpdf/logs" \
  "$APPDATA/calibreweb" \
  "$APPDATA/ntfy/cache" \
  "$APPDATA/ntfy/etc" \
  "$APPDATA/prowlarr" \
  "$APPDATA/sonarr" \
  "$APPDATA/radarr" \
  "$APPDATA/minecraft" \
  "$APPDATA/tailscale" \
  "$APPDATA/minecraft-tailscale" \
  "$APPDATA/other" \
  "$APPDATA/uptime-kuma" \
  "$APPDATA/autokuma"

echo "Creating media folders under $MEDIA ..."
mkdir -p \
  "$MEDIA/movies" \
  "$MEDIA/tv" \
  "$MEDIA/downloads" \
  "$MEDIA/books" \
  "$MEDIA/calibreweb-ingest"

# .env from example, only if it doesn't already exist
if [ -f "$ENV_DIR/.env.example" ] && [ ! -f "$ENV_DIR/.env" ]; then
  echo "Creating .env from .env.example - EDIT THIS before starting the stack."
  cp "$ENV_DIR/.env.example" "$ENV_DIR/.env"
  chown "$REAL_USER" "$ENV_DIR/.env"

  # Try to auto-detect the server's LAN IP and pre-fill SERVER_IP in .env
  DETECTED_IP=$(sudo -u "$REAL_USER" hostname -I 2>/dev/null | awk '{print $1}')
  if [ -n "$DETECTED_IP" ]; then
    sed -i "s/^SERVER_IP=.*/SERVER_IP=${DETECTED_IP}/" "$ENV_DIR/.env"
    echo "Detected LAN IP: $DETECTED_IP - pre-filled as SERVER_IP in .env."
    echo "Double check this is correct (matches your router's subnet) before starting."
  else
    echo "Could not auto-detect an IP - set SERVER_IP in .env manually."
  fi
else
  echo "Skipping .env creation (already exists, or .env.example not found)."
fi

# ---------------------------------------------------------------------------
# Plex dynamic Traefik config
#
# Plex runs with network_mode: host, so Traefik's Docker label-based
# discovery can't reach it (no Docker-network IP to route to). Instead,
# Traefik's file provider is used to manually define a router + service
# pointing straight at the host's LAN IP on Plex's port (32400). This file
# is regenerated on every run, so any manual edits you've made to plex.yml
# will be overwritten - re-run this script after changing .env if you need
# those changes picked up.
# ---------------------------------------------------------------------------
PLEX_DYNAMIC_FILE="$APPDATA/traefik/dynamic/plex.yml"
echo "Writing Traefik dynamic config for Plex at $PLEX_DYNAMIC_FILE ..."

# Reuse the LAN IP detected above if we have it; otherwise try again here
PLEX_IP="${DETECTED_IP:-$(sudo -u "$REAL_USER" hostname -I 2>/dev/null | awk '{print $1}')}"

if [ -n "$PLEX_IP" ]; then
  # Try to read DOMAIN_NAME from .env so the rule is pre-filled correctly
  DOMAIN_NAME_VALUE=""
  if [ -f "$ENV_DIR/.env" ]; then
    DOMAIN_NAME_VALUE=$(grep -E '^DOMAIN_NAME=' "$ENV_DIR/.env" | cut -d '=' -f2-)
  fi
  DOMAIN_NAME_VALUE="${DOMAIN_NAME_VALUE:-yourdomain.com}"

  cat > "$PLEX_DYNAMIC_FILE" << EOF
http:
  routers:
    plex:
      rule: "Host(\`plex.${DOMAIN_NAME_VALUE}\`)"
      entrypoints:
        - websecure
      tls:
        certResolver: cloudflare
      service: plex-svc

  services:
    plex-svc:
      loadBalancer:
        servers:
          - url: "http://${PLEX_IP}:32400"
EOF
  echo "Plex dynamic config written using detected IP ($PLEX_IP) and domain (${DOMAIN_NAME_VALUE})."
  echo "Double check both are correct in $PLEX_DYNAMIC_FILE before relying on it."
else
  echo "Could not auto-detect an IP - skipping plex.yml generation."
  echo "Create $PLEX_DYNAMIC_FILE manually, see the docker-compose.yml comment on the plex service."
fi

echo "Handing folder ownership to $REAL_USER ..."
chown -R "$REAL_USER":"$REAL_USER" "$APPDATA" "$MEDIA"

echo ""
echo "Done. Folder structure ready at $APPDATA and $MEDIA."
echo "Next steps:"
echo "  1. Edit .env - confirm SERVER_IP is correct, and set your timezone,"
echo "     paths, and passwords."
echo "  2. Run: docker compose up -d"