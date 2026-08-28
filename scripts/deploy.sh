#!/usr/bin/env bash

set -euo pipefail

cd "$HOME/home-server"

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
sudo -n ./scripts/generate-homepage.sh
echo "    Homepage configuration generated successfully."
echo

echo "==> Running server setup"
sudo -n ./scripts/setup.sh
echo "    Server setup completed successfully."
echo

echo "==> Validating Docker Compose configuration"
docker compose config --quiet
echo "    Docker Compose configuration is valid."
echo

echo "==> Deploying containers"
docker compose up -d --force-recreate --remove-orphans
echo "    Containers deployed successfully."
echo

echo "==> Checking container status"
docker compose ps
echo

echo "========================================"
echo "       Deployment Complete"
echo "========================================"
echo
