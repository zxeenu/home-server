#!/usr/bin/env bash

set -euo pipefail

LOG_TAG="[homepage-gen]"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
TEMPLATE_HTML="${PROJECT_ROOT}/templates/index.html"
TEMPLATE_SERVICES="${PROJECT_ROOT}/templates/services.json"
OUTPUT_HTML="${PROJECT_ROOT}/index.html"
OUTPUT_SERVICES="${PROJECT_ROOT}/services.json"


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

[[ -f "$TEMPLATE_HTML" ]] \
    || error "HTML template not found: $TEMPLATE_HTML"

[[ -f "$TEMPLATE_SERVICES" ]] \
    || error "Services template not found: $TEMPLATE_SERVICES"


# ---------------------------------------------------------------------------
# Load .env
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

[[ -n "$DOMAIN_NAME" ]] || error "DOMAIN_NAME is missing from .env"
[[ -n "$SERVER_IP" ]]   || error "SERVER_IP is missing from .env"
[[ -n "$NTFY_TOPIC" ]]  || error "NTFY_TOPIC is missing from .env"
[[ -n "$HOMEPAGE_PORT" ]] || error "HOMEPAGE_PORT is missing from .env"


# ---------------------------------------------------------------------------
# Optional notes (for services)
# ---------------------------------------------------------------------------

NOTE_PLEX="${NOTE_PLEX:-}"
NOTE_QBITTORRENT="${NOTE_QBITTORRENT:-}"
NOTE_PIHOLE="${NOTE_PIHOLE:-}"
NOTE_PORTAINER="${NOTE_PORTAINER:-}"
NOTE_TRAEFIK="${NOTE_TRAEFIK:-}"
NOTE_STIRLINGPDF="${NOTE_STIRLINGPDF:-}"
NOTE_NTFY="${NOTE_NTFY:-}"
NOTE_CALIBREWEB="${NOTE_CALIBREWEB:-}"

export \
    DOMAIN_NAME \
    SERVER_IP \
    NTFY_TOPIC \
    HOMEPAGE_PORT \
    NOTE_PLEX \
    NOTE_QBITTORRENT \
    NOTE_PIHOLE \
    NOTE_PORTAINER \
    NOTE_TRAEFIK \
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
# Generate HTML
# ---------------------------------------------------------------------------

log "Project root: $PROJECT_ROOT"
log "HTML template: $TEMPLATE_HTML"
log "HTML output:   $OUTPUT_HTML"
log "Domain:        $DOMAIN_NAME"
log "Server IP:     $SERVER_IP"

HTML_TMP="$(mktemp)"

cleanup() {
    rm -f "$HTML_TMP" "$SERVICES_TMP"
}
trap cleanup EXIT

perl -0pe '
my %values = (
    "DOMAIN_NAME"    => $ENV{"DOMAIN_NAME"} // "",
    "SERVER_IP"      => $ENV{"SERVER_IP"} // "",
    "NTFY_TOPIC"     => $ENV{"NTFY_TOPIC"} // "",
    "HOMEPAGE_PORT"  => $ENV{"HOMEPAGE_PORT"} // "",
);

s{
    \{\{([A-Z0-9_]+)\}\}
}{
    exists $values{$1} ? $values{$1} : $&
}gex;
' "$TEMPLATE_HTML" > "$HTML_TMP"

chmod 644 "$HTML_TMP"


# ---------------------------------------------------------------------------
# Generate services.json
# ---------------------------------------------------------------------------

log "Services template: $TEMPLATE_SERVICES"
log "Services output:   $OUTPUT_SERVICES"

SERVICES_TMP="$(mktemp)"

perl -0pe '
my %values = (
    "DOMAIN_NAME"    => $ENV{"DOMAIN_NAME"} // "",
    "SERVER_IP"      => $ENV{"SERVER_IP"} // "",
    "NOTE_PLEX"              => $ENV{"NOTE_PLEX"} // "",
    "NOTE_QBITTORRENT"       => $ENV{"NOTE_QBITTORRENT"} // "",
    "NOTE_PIHOLE"            => $ENV{"NOTE_PIHOLE"} // "",
    "NOTE_PORTAINER"         => $ENV{"NOTE_PORTAINER"} // "",
    "NOTE_TRAEFIK"           => $ENV{"NOTE_TRAEFIK"} // "",
    "NOTE_STIRLINGPDF"       => $ENV{"NOTE_STIRLINGPDF"} // "",
    "NOTE_NTFY"              => $ENV{"NOTE_NTFY"} // "",
    "NOTE_CALIBREWEB"        => $ENV{"NOTE_CALIBREWEB"} // "",
);

s{
    \{\{([A-Z0-9_]+)\}\}
}{
    exists $values{$1} ? $values{$1} : $&
}gex;
' "$TEMPLATE_SERVICES" > "$SERVICES_TMP"

chmod 644 "$SERVICES_TMP"


# ---------------------------------------------------------------------------
# Atomic replacements
# ---------------------------------------------------------------------------

mv "$HTML_TMP" "$OUTPUT_HTML"
mv "$SERVICES_TMP" "$OUTPUT_SERVICES"

trap - EXIT


# ---------------------------------------------------------------------------
# Verify HTML
# ---------------------------------------------------------------------------

log "HTML generated successfully."
ls -lah "$OUTPUT_HTML"

echo
log "Checking for unreplaced template variables in HTML..."
if grep -oE '\{\{[A-Z0-9_]+\}\}' "$OUTPUT_HTML" | sort -u; then
    echo
    log "WARNING: The HTML template contains variables that were not replaced."
else
    log "All HTML template variables replaced."
fi

# ---------------------------------------------------------------------------
# Verify JSON
# ---------------------------------------------------------------------------

log "services.json generated successfully."
ls -lah "$OUTPUT_SERVICES"

echo
log "Checking for unreplaced template variables in services.json..."
if grep -oE '\{\{[A-Z0-9_]+\}\}' "$OUTPUT_SERVICES" | sort -u; then
    echo
    log "WARNING: The services template contains variables that were not replaced."
else
    log "All services template variables replaced."
fi