#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# -------------------------------------------------------------------
# Helper: check if a service container is running
# -------------------------------------------------------------------
check_container() {
    local service="$1"
    local status
    status=$(docker compose ps --format json "$service" 2>/dev/null | jq -r '.[0].State' 2>/dev/null || echo "unknown")
    if [[ "$status" == "running" ]]; then
        echo -e "  ${GREEN}✔${NC} $service is running"
        return 0
    else
        echo -e "  ${RED}✘${NC} $service is NOT running (state: $status)"
        return 1
    fi
}

# -------------------------------------------------------------------
# Helper: check an HTTP endpoint (internal Docker DNS)
# -------------------------------------------------------------------
check_http() {
    local service="$1"
    local url="$2"
    local expected_codes="${3:-200}"
    local code
    # Use curl with a timeout, follow redirects (for services like Portainer)
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
    # Check if code is in expected_codes (comma-separated)
    if [[ ",$expected_codes," == *",$code,"* ]]; then
        echo -e "  ${GREEN}✔${NC} $service HTTP $url -> $code (expected: $expected_codes)"
        return 0
    else
        echo -e "  ${RED}✘${NC} $service HTTP $url -> $code (expected: $expected_codes)"
        return 1
    fi
}

# -------------------------------------------------------------------
# Main verification
# -------------------------------------------------------------------
echo "=================================================="
echo "  HOME SERVER STACK – VERIFICATION"
echo "=================================================="

# Check that we are in the right directory (compose file exists)
if [[ ! -f "docker-compose.yml" ]]; then
    echo -e "${RED}ERROR: docker-compose.yml not found in current directory.${NC}"
    exit 1
fi

# 1. Container running status
echo
echo "--- Container status ---"

services=(
    "docker-proxy-ro"
    "docker-proxy-rw"
    "homepage"
    "traefik"
    "portainer"
    "pihole"
    "plex"
    "qbittorrent"
    "stirlingpdf"
    "calibreweb"
    "ntfy"
    "samba"
    "tailscale"
    "uptime-kuma"
    "autokuma"
)

all_ok=true
for svc in "${services[@]}"; do
    if ! check_container "$svc"; then
        all_ok=false
    fi
done

# 2. HTTP endpoint checks (only for services with web UIs)
echo
echo "--- HTTP endpoint checks (internal Docker DNS) ---"

# Define endpoints: "service_name" "url" "expected_codes"
http_tests=(
    "Traefik"          "http://traefik:80/ping"                "200"
    "Homepage"         "http://homepage:80"                    "200"
    "Portainer"        "http://portainer:9000"                "200,302"   # may redirect to /#!/auth
    "Pi-hole Admin"    "http://pihole:80/admin"               "200"
    "qBittorrent"      "http://qbittorrent:8080"              "200,302"   # may redirect to /login
    "Stirling PDF"     "http://stirlingpdf:8080"              "200"
    "Calibre-Web"      "http://calibreweb:8083"               "200"
    "ntfy"             "http://ntfy:80/v1/health"             "200"
    "Uptime Kuma"      "http://uptime-kuma:3001"              "200"
    # Proxies themselves (optional)
    "docker-proxy-ro"  "http://docker-proxy-ro:2375/version"  "200"
    "docker-proxy-rw"  "http://docker-proxy-rw:2375/version"  "200"
)

for test in "${http_tests[@]}"; do
    # Split: we assume fields are space-separated; service name may have spaces, so we parse carefully.
    # We'll use a read with three variables, but we need to handle spaces in names.
    # Simpler: use array and shift.
    # We'll use IFS to parse: format "Service Name" "url" "codes"
    # But easier: we define tests as "service|url|codes" and split on '|'
    # We'll convert the array to that format.
    # Let's rebuild the tests with pipe separators.
    tests=(
        "Traefik|http://traefik:80/ping|200"
        "Homepage|http://homepage:80|200"
        "Portainer|http://portainer:9000|200,302"
        "Pi-hole Admin|http://pihole:80/admin|200"
        "qBittorrent|http://qbittorrent:8080|200,302"
        "Stirling PDF|http://stirlingpdf:8080|200"
        "Calibre-Web|http://calibreweb:8083|200"
        "ntfy|http://ntfy:80/v1/health|200"
        "Uptime Kuma|http://uptime-kuma:3001|200"
        "docker-proxy-ro|http://docker-proxy-ro:2375/version|200"
        "docker-proxy-rw|http://docker-proxy-rw:2375/version|200"
    )
    # We'll loop over these tests
done

# We'll rebuild with the pipe format and loop
test_items=(
    "Traefik|http://traefik:80/ping|200"
    "Homepage|http://homepage:80|200"
    "Portainer|http://portainer:9000|200,302"
    "Pi-hole Admin|http://pihole:80/admin|200"
    "qBittorrent|http://qbittorrent:8080|200,302"
    "Stirling PDF|http://stirlingpdf:8080|200"
    "Calibre-Web|http://calibreweb:8083|200"
    "ntfy|http://ntfy:80/v1/health|200"
    "Uptime Kuma|http://uptime-kuma:3001|200"
    "docker-proxy-ro|http://docker-proxy-ro:2375/version|200"
    "docker-proxy-rw|http://docker-proxy-rw:2375/version|200"
)

for item in "${test_items[@]}"; do
    IFS='|' read -r name url codes <<< "$item"
    if ! check_http "$name" "$url" "$codes"; then
        all_ok=false
    fi
done

# 3. Optional: check that Pi‑hole DNS is resolving correctly? (not necessary)

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo
if $all_ok; then
    echo -e "${GREEN}✅ All services are running and passing basic checks.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some checks failed. Review the output above.${NC}"
    exit 1
fi