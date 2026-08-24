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
set -e

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
  "$APPDATA/npm/data" \
  "$APPDATA/npm/letsencrypt" \
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
  "${APPDATA}/other"

echo "Creating media folders under $MEDIA ..."
mkdir -p \
  "$MEDIA/movies" \
  "$MEDIA/tv" \
  "$MEDIA/downloads" \
  "$MEDIA/books"

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

echo "Handing folder ownership to $REAL_USER ..."
chown -R "$REAL_USER":"$REAL_USER" "$APPDATA" "$MEDIA"

echo ""
echo "Done. Folder structure ready at $APPDATA and $MEDIA."
echo "Next steps:"
echo "  1. Edit .env - confirm SERVER_IP is correct, and set your timezone,"
echo "     paths, and passwords."
echo "  2. Run: docker compose up -d"