#!/usr/bin/env bash

set -euo pipefail

HOME_SERVER="$HOME/home-server"
MINECRAFT="$HOME_SERVER/subsetup/minecraft"
MINECRAFT_TAILSCALE="$HOME_SERVER/subsetup/minecraft-tailscale"

cd "$HOME_SERVER"

echo
echo "========================================"
echo "       Home Server Deployment"
echo "========================================"
echo

echo "==> Working directory"
pwd
echo

echo "==> Pulling latest configuration"
git pull --ff-only origin main
echo "    Configuration updated successfully."
echo

echo "==> Generating Homepage configuration"
sudo -n "$HOME_SERVER/scripts/generate-homepage.sh"
echo "    Homepage configuration generated successfully."
echo

echo "==> Running server setup"
sudo -n "$HOME_SERVER/scripts/setup.sh"
echo "    Server setup completed successfully."
echo

echo "==> Validating Home Server Docker Compose configuration"
docker compose config --quiet
echo "    Home Server Compose configuration is valid."
echo

echo "==> Validating Minecraft Docker Compose configuration"
cd "$MINECRAFT"
docker compose config --quiet
echo "    Minecraft Compose configuration is valid."
echo

echo "==> Validating Minecraft Tailscale Docker Compose configuration"
cd "$MINECRAFT_TAILSCALE"
docker compose config --quiet
echo "    Minecraft Tailscale Compose configuration is valid."
echo

echo "========================================"
echo "       Configuration Validated"
echo "========================================"
echo

echo "==> Deploying Home Server containers"
cd "$HOME_SERVER"
docker compose down --remove-orphans
docker compose up -d --force-recreate --remove-orphans
echo "    Home Server containers deployed successfully."
echo

echo "==> Deploying Minecraft containers"
cd "$MINECRAFT"
docker compose down --remove-orphans
docker compose up -d --force-recreate --remove-orphans
echo "    Minecraft containers deployed successfully."
echo

echo "==> Deploying Minecraft Tailscale containers"
cd "$MINECRAFT_TAILSCALE"
docker compose down --remove-orphans
docker compose up -d --force-recreate --remove-orphans
echo "    Minecraft Tailscale containers deployed successfully."
echo

echo "========================================"
echo "       Container Status"
echo "========================================"
echo

echo "==> Home Server"
cd "$HOME_SERVER"
docker compose ps

echo
echo "==> Minecraft"
cd "$MINECRAFT"
docker compose ps

echo
echo "==> Minecraft Tailscale"
cd "$MINECRAFT_TAILSCALE"
docker compose ps

echo
echo "========================================"
echo "       Deployment Complete"
echo "========================================"
echo
