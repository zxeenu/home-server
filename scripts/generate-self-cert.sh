#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# generate-self-cert.sh - creates a self-signed wildcard SSL certificate for
# your domain (DOMAIN_NAME) and *.DOMAIN_NAME, valid for 10 years. Use this
# to enable HTTPS in Nginx Proxy Manager for your local domains.
#
# NOTE: this script now lives in a subfolder. It reads DOMAIN_NAME from the
# .env file one directory up (same place docker-compose.yml lives).
#
# Usage:
#   chmod +x generate-cert.sh
#   ./generate-cert.sh
#
# After running, upload the two output files to NPM:
#   SSL Certificates -> Add SSL Certificate -> Custom
#     Certificate      -> paste contents of <domain>.crt
#     Certificate Key  -> paste contents of <domain>.key
# ---------------------------------------------------------------------------
set -e

# Where .env lives, relative to this script's location
ENV_DIR="$(dirname "$0")/.."
ENV_FILE="$ENV_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  # Pull just the DOMAIN_NAME value out of .env without sourcing the
  # whole file (safer if .env has other stuff in it).
  DOMAIN_NAME=$(grep -E '^DOMAIN_NAME=' "$ENV_FILE" | tail -n1 | cut -d '=' -f2-)
  # strip surrounding quotes, if any
  DOMAIN_NAME="${DOMAIN_NAME%\"}"
  DOMAIN_NAME="${DOMAIN_NAME#\"}"
  DOMAIN_NAME="${DOMAIN_NAME%\'}"
  DOMAIN_NAME="${DOMAIN_NAME#\'}"
fi

if [ -z "$DOMAIN_NAME" ]; then
  echo "Could not find DOMAIN_NAME in $ENV_FILE."
  echo "Set it in your .env (e.g. DOMAIN_NAME=home.lan) and re-run, or export it manually:"
  echo "  DOMAIN_NAME=home.lan ./generate-cert.sh"
  exit 1
fi

DOMAIN="$DOMAIN_NAME"
OUT_DIR="./homelab-cert"
DAYS=3650   # 10 years

mkdir -p "$OUT_DIR"

echo "Generating self-signed wildcard certificate for $DOMAIN and *.$DOMAIN ..."

openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
  -keyout "$OUT_DIR/$DOMAIN.key" \
  -out "$OUT_DIR/$DOMAIN.crt" \
  -subj "/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN"

# Double-check the key has no passphrase (NPM rejects encrypted keys).
# -nodes above should already ensure this, but this makes it explicit/certain.
openssl rsa -in "$OUT_DIR/$DOMAIN.key" -out "$OUT_DIR/$DOMAIN.key" 2>/dev/null || true

echo ""
echo "Done. Files created in $OUT_DIR/:"
echo "  - $DOMAIN.crt  (the certificate - paste into NPM's 'Certificate' field)"
echo "  - $DOMAIN.key  (the private key  - paste into NPM's 'Certificate Key' field)"
echo ""
echo "Next steps:"
echo "  1. cat $OUT_DIR/$DOMAIN.crt   -> copy the output"
echo "  2. cat $OUT_DIR/$DOMAIN.key   -> copy the output"
echo "  3. In NPM: SSL Certificates -> Add SSL Certificate -> Custom"
echo "     Paste each into its matching field, name it, and save."
echo "  4. Edit each Proxy Host -> SSL tab -> select this certificate -> enable Force SSL."
echo ""
echo "Note: browsers will show a one-time trust warning per device since this"
echo "certificate isn't from a public authority - that's expected for a local domain."