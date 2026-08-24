#!/usr/bin/env bash

set -euo pipefail

LOG_TAG="[homepage-gen]"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
TEMPLATE="${PROJECT_ROOT}/templates/index.html.template"
OUTPUT="${PROJECT_ROOT}/index.html"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

error() {
    echo "${LOG_TAG} ERROR: $*" >&2
    exit 1
}

log() {
    echo "${LOG_TAG} $*"
}


# ---------------------------------------------------------------------------
# Check files
# ---------------------------------------------------------------------------

[[ -f "$ENV_FILE" ]] \
    || error ".env not found: $ENV_FILE"

[[ -f "$TEMPLATE" ]] \
    || error "template not found: $TEMPLATE"


# ---------------------------------------------------------------------------
# Load .env
#
# We deliberately use `source` here because this allows normal .env syntax:
#
#   SERVER_IP=192.168.100.65
#   NOTE_PLEX="Direct play preferred"
#
# Values containing spaces MUST be quoted.
# ---------------------------------------------------------------------------

set -a

# shellcheck disable=SC1090
source "$ENV_FILE"

set +a


# ---------------------------------------------------------------------------
# Required configuration
# ---------------------------------------------------------------------------

DOMAIN_NAME="${DOMAIN_NAME:-}"
SERVER_IP="${SERVER_IP:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
HOMEPAGE_PORT="${HOMEPAGE_PORT:-}"

[[ -n "$DOMAIN_NAME" ]] \
    || error "DOMAIN_NAME is missing from .env"

[[ -n "$SERVER_IP" ]] \
    || error "SERVER_IP is missing from .env"

[[ -n "$NTFY_TOPIC" ]] \
    || error "NTFY_TOPIC is missing from .env"

[[ -n "$HOMEPAGE_PORT" ]] \
    || error "HOMEPAGE_PORT is missing from .env"


# ---------------------------------------------------------------------------
# Optional notes
#
# Every service can have a note.
# If the variable doesn't exist, it becomes an empty string.
# ---------------------------------------------------------------------------

NOTE_PLEX="${NOTE_PLEX:-}"
NOTE_QBITTORRENT="${NOTE_QBITTORRENT:-}"
NOTE_PIHOLE="${NOTE_PIHOLE:-}"
NOTE_PORTAINER="${NOTE_PORTAINER:-}"
NOTE_NGINXPROXYMANAGER="${NOTE_NGINXPROXYMANAGER:-}"
NOTE_STIRLINGPDF="${NOTE_STIRLINGPDF:-}"
NOTE_NTFY="${NOTE_NTFY:-}"
NOTE_CALIBREWEB="${NOTE_CALIBREWEB:-}"


# ---------------------------------------------------------------------------
# Export everything used by Perl
# ---------------------------------------------------------------------------

export \
    DOMAIN_NAME \
    SERVER_IP \
    NTFY_TOPIC \
    HOMEPAGE_PORT \
    NOTE_PLEX \
    NOTE_QBITTORRENT \
    NOTE_PIHOLE \
    NOTE_PORTAINER \
    NOTE_NGINXPROXYMANAGER \
    NOTE_STIRLINGPDF \
    NOTE_NTFY \
    NOTE_CALIBREWEB


# ---------------------------------------------------------------------------
# Check Perl
# ---------------------------------------------------------------------------

if ! command -v perl >/dev/null 2>&1; then
    error "Perl is required. Install it with: sudo apt install perl"
fi


# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------

log "Project root: $PROJECT_ROOT"
log "Template:     $TEMPLATE"
log "Output:       $OUTPUT"
log "Domain:       $DOMAIN_NAME"
log "Server IP:    $SERVER_IP"


TMP_FILE="$(mktemp)"

cleanup() {
    rm -f "$TMP_FILE"
}

trap cleanup EXIT


# ---------------------------------------------------------------------------
# Replace template variables
# ---------------------------------------------------------------------------

perl -0pe '
my %values = (
    "DOMAIN_NAME"              => $ENV{"DOMAIN_NAME"} // "",
    "SERVER_IP"                => $ENV{"SERVER_IP"} // "",
    "NTFY_TOPIC"               => $ENV{"NTFY_TOPIC"} // "",
    "HOMEPAGE_PORT"            => $ENV{"HOMEPAGE_PORT"} // "",

    "NOTE_PLEX"                => $ENV{"NOTE_PLEX"} // "",
    "NOTE_QBITTORRENT"         => $ENV{"NOTE_QBITTORRENT"} // "",
    "NOTE_PIHOLE"              => $ENV{"NOTE_PIHOLE"} // "",
    "NOTE_PORTAINER"           => $ENV{"NOTE_PORTAINER"} // "",
    "NOTE_NGINXPROXYMANAGER"   => $ENV{"NOTE_NGINXPROXYMANAGER"} // "",
    "NOTE_STIRLINGPDF"         => $ENV{"NOTE_STIRLINGPDF"} // "",
    "NOTE_NTFY"                => $ENV{"NOTE_NTFY"} // "",
    "NOTE_CALIBREWEB"          => $ENV{"NOTE_CALIBREWEB"} // "",
);

s{
    \{\{([A-Z0-9_]+)\}\}
}{
    exists $values{$1}
        ? $values{$1}
        : $&
}gex;
' "$TEMPLATE" > "$TMP_FILE"


# ---------------------------------------------------------------------------
# Ensure nginx can read the file
# ---------------------------------------------------------------------------

chmod 644 "$TMP_FILE"


# ---------------------------------------------------------------------------
# Atomic replacement
# ---------------------------------------------------------------------------

mv "$TMP_FILE" "$OUTPUT"

trap - EXIT


# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

log "Generated successfully."
log "Permissions:"
ls -lah "$OUTPUT"

echo
log "Checking for unreplaced template variables..."

if grep -oE '\{\{[A-Z0-9_]+\}\}' "$OUTPUT" | sort -u; then
    echo
    log "WARNING: The template contains variables that were not replaced."
else
    log "All template variables replaced."
fi