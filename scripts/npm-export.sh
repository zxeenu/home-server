#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# npm-export.sh - Export Nginx Proxy Manager configuration to JSON
#
# Writes to:
#   <project-root>/config/npm-export-YYYY-MM-DD_HH-MM-SS.json
#
# Project layout:
#
#   home-server-setup/
#   ├── .env
#   ├── docker-compose.yml
#   ├── config/
#   └── scripts/
#       └── npm-export.sh
#
# The script assumes it lives in:
#   <project-root>/scripts/
#
# Required environment variables:
#   DOMAIN_NAME
#   IP_ADDRESS
#   NPM_EMAIL
#   NPM_PASSWORD
#
# DOMAIN_NAME and IP_ADDRESS are also read from <project-root>/.env
# if they are not already exported.
#
# Dependencies:
#   curl
#   jq
# ---------------------------------------------------------------------------

LOG_TAG="[npm-export]"

# ---------------------------------------------------------------------------
# Project paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
CONFIG_DIR="${PROJECT_ROOT}/config"

mkdir -p "${CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Read a value from .env
# ---------------------------------------------------------------------------

read_env_value() {
    local key="$1"
    local value=""

    if [[ -f "${ENV_FILE}" ]]; then
        value="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n1 | cut -d '=' -f2- || true)"

        # Remove surrounding double quotes
        value="${value%\"}"
        value="${value#\"}"

        # Remove surrounding single quotes
        value="${value%\'}"
        value="${value#\'}"
    fi

    echo "${value}"
}

# ---------------------------------------------------------------------------
# Domain
# ---------------------------------------------------------------------------

if [[ -z "${DOMAIN_NAME:-}" ]]; then
    DOMAIN_NAME="$(read_env_value "DOMAIN_NAME")"
fi

if [[ -z "${DOMAIN_NAME:-}" ]]; then
    echo "${LOG_TAG} ERROR: DOMAIN_NAME is not set."
    echo "${LOG_TAG} Set DOMAIN_NAME in ${ENV_FILE} or export it."
    exit 1
fi

# ---------------------------------------------------------------------------
# IP address
# ---------------------------------------------------------------------------

if [[ -z "${IP_ADDRESS:-}" ]]; then
    IP_ADDRESS="$(read_env_value "IP_ADDRESS")"
fi

if [[ -z "${IP_ADDRESS:-}" ]]; then
    echo "${LOG_TAG} ERROR: IP_ADDRESS is not set."
    echo "${LOG_TAG} Set IP_ADDRESS in ${ENV_FILE} or export it."
    exit 1
fi

# ---------------------------------------------------------------------------
# NPM credentials
#
# These should come from ~/.zshrc:
#
#   export NPM_EMAIL="..."
#   export NPM_PASSWORD="..."
#
# Do NOT put them in the project .env.
# ---------------------------------------------------------------------------

NPM_EMAIL="${NPM_EMAIL:-}"
NPM_PASSWORD="${NPM_PASSWORD:-}"

if [[ -z "${NPM_EMAIL}" || -z "${NPM_PASSWORD}" ]]; then
    echo "${LOG_TAG} ERROR: NPM_EMAIL and/or NPM_PASSWORD are not set."
    echo
    echo "${LOG_TAG} If they are in ~/.zshrc, run:"
    echo
    echo "    ./npm-export.sh"
    echo
    echo "${LOG_TAG} If sudo is required, run:"
    echo
    echo "    sudo --preserve-env=NPM_EMAIL,NPM_PASSWORD bash npm-export.sh"
    echo
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

for command in curl jq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "${LOG_TAG} ERROR: '${command}' is required but was not found."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# NPM hosts
#
# Try DNS name first, then direct IP fallback.
# ---------------------------------------------------------------------------

NPM_HOSTS=(
    "proxy.${DOMAIN_NAME}:81"
    "${IP_ADDRESS}:81"
)

# ---------------------------------------------------------------------------
# Temporary working directory
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
OUTPUT_FILE="${CONFIG_DIR}/npm-export-${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Authenticate
# ---------------------------------------------------------------------------

get_token() {
    local base_url="$1"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        -X POST \
        "http://${base_url}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "$(
            jq -n \
                --arg identity "${NPM_EMAIL}" \
                --arg secret "${NPM_PASSWORD}" \
                '{
                    identity: $identity,
                    secret: $secret
                }'
        )" \
        | jq -r '.token // empty'
}

# ---------------------------------------------------------------------------
# GET helper
# ---------------------------------------------------------------------------

npm_get() {
    local base_url="$1"
    local token="$2"
    local endpoint="$3"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X GET \
        "http://${base_url}${endpoint}" \
        -H "Authorization: Bearer ${token}"
}

# ---------------------------------------------------------------------------
# Find working NPM host
# ---------------------------------------------------------------------------

NPM_BASE_URL=""
NPM_TOKEN=""

for host in "${NPM_HOSTS[@]}"; do
    echo "${LOG_TAG} Trying ${host} ..."

    token="$(get_token "${host}" 2>/dev/null || true)"

    if [[ -z "${token}" ]]; then
        echo "${LOG_TAG} ${host}: authentication failed, trying next host"
        continue
    fi

    echo "${LOG_TAG} ${host}: authenticated successfully"

    NPM_BASE_URL="${host}"
    NPM_TOKEN="${token}"

    break
done

if [[ -z "${NPM_BASE_URL}" ]]; then
    echo "${LOG_TAG} ERROR: Could not authenticate with any NPM host."
    exit 1
fi

# ---------------------------------------------------------------------------
# Export one endpoint
# ---------------------------------------------------------------------------

export_endpoint() {
    local name="$1"
    local endpoint="$2"
    local output="$3"

    echo "${LOG_TAG} Exporting ${name}..."

    if ! npm_get \
        "${NPM_BASE_URL}" \
        "${NPM_TOKEN}" \
        "${endpoint}" \
        > "${output}"; then

        echo "${LOG_TAG} ${name}: FAILED"
        return 1
    fi

    if ! jq empty "${output}" >/dev/null 2>&1; then
        echo "${LOG_TAG} ${name}: returned invalid JSON"
        return 1
    fi

    echo "${LOG_TAG} ${name}: OK"
    return 0
}

# ---------------------------------------------------------------------------
# Export all NPM configuration
#
# These correspond to the current NPM API routes.
# ---------------------------------------------------------------------------

FAILED_ENDPOINTS=()

export_endpoint \
    "proxy hosts" \
    "/api/nginx/proxy-hosts" \
    "${TMP_DIR}/proxy-hosts.json" \
    || FAILED_ENDPOINTS+=("proxy_hosts")

export_endpoint \
    "redirection hosts" \
    "/api/nginx/redirection-hosts" \
    "${TMP_DIR}/redirection-hosts.json" \
    || FAILED_ENDPOINTS+=("redirection_hosts")

export_endpoint \
    "dead hosts" \
    "/api/nginx/dead-hosts" \
    "${TMP_DIR}/dead-hosts.json" \
    || FAILED_ENDPOINTS+=("dead_hosts")

export_endpoint \
    "streams" \
    "/api/nginx/streams" \
    "${TMP_DIR}/streams.json" \
    || FAILED_ENDPOINTS+=("streams")

export_endpoint \
    "access lists" \
    "/api/nginx/access-lists" \
    "${TMP_DIR}/access-lists.json" \
    || FAILED_ENDPOINTS+=("access_lists")

export_endpoint \
    "certificates" \
    "/api/nginx/certificates" \
    "${TMP_DIR}/certificates.json" \
    || FAILED_ENDPOINTS+=("certificates")

export_endpoint \
    "settings" \
    "/api/settings" \
    "${TMP_DIR}/settings.json" \
    || FAILED_ENDPOINTS+=("settings")

export_endpoint \
    "users" \
    "/api/users" \
    "${TMP_DIR}/users.json" \
    || FAILED_ENDPOINTS+=("users")

# ---------------------------------------------------------------------------
# Replace failed exports with safe empty values
# ---------------------------------------------------------------------------

for name in \
    proxy-hosts \
    redirection-hosts \
    dead-hosts \
    streams \
    access-lists \
    certificates \
    users
do
    if [[ ! -f "${TMP_DIR}/${name}.json" ]]; then
        echo "[]" > "${TMP_DIR}/${name}.json"
    fi
done

if [[ ! -f "${TMP_DIR}/settings.json" ]]; then
    echo "{}" > "${TMP_DIR}/settings.json"
fi

# ---------------------------------------------------------------------------
# Build final JSON
# ---------------------------------------------------------------------------

echo "${LOG_TAG} Building final export..."

jq -n \
    --arg exported_at "$(date --iso-8601=seconds)" \
    --arg domain_name "${DOMAIN_NAME}" \
    --arg npm_host "${NPM_BASE_URL}" \
    --argjson failed_endpoints "$(printf '%s\n' "${FAILED_ENDPOINTS[@]:-}" | jq -R . | jq -s .)" \
    --slurpfile proxy_hosts "${TMP_DIR}/proxy-hosts.json" \
    --slurpfile redirection_hosts "${TMP_DIR}/redirection-hosts.json" \
    --slurpfile dead_hosts "${TMP_DIR}/dead-hosts.json" \
    --slurpfile streams "${TMP_DIR}/streams.json" \
    --slurpfile access_lists "${TMP_DIR}/access-lists.json" \
    --slurpfile certificates "${TMP_DIR}/certificates.json" \
    --slurpfile settings "${TMP_DIR}/settings.json" \
    --slurpfile users "${TMP_DIR}/users.json" \
    '{
        version: 1,
        exported_at: $exported_at,
        domain_name: $domain_name,
        npm_host: $npm_host,

        failed_endpoints: $failed_endpoints,

        proxy_hosts: $proxy_hosts[0],
        redirection_hosts: $redirection_hosts[0],
        dead_hosts: $dead_hosts[0],
        streams: $streams[0],
        access_lists: $access_lists[0],
        certificates: $certificates[0],
        settings: $settings[0],
        users: $users[0]
    }' \
    > "${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Validate final JSON
# ---------------------------------------------------------------------------

if ! jq empty "${OUTPUT_FILE}" >/dev/null 2>&1; then
    echo "${LOG_TAG} ERROR: Generated export is invalid JSON."
    rm -f "${OUTPUT_FILE}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "${LOG_TAG} ==============================================="
echo "${LOG_TAG} NPM configuration exported successfully"
echo "${LOG_TAG} ==============================================="
echo "${LOG_TAG} NPM host: ${NPM_BASE_URL}"
echo "${LOG_TAG} Output:   ${OUTPUT_FILE}"
echo "${LOG_TAG} Size:     $(du -h "${OUTPUT_FILE}" | cut -f1)"

if [[ "${#FAILED_ENDPOINTS[@]}" -gt 0 ]]; then
    echo
    echo "${LOG_TAG} WARNING: Some endpoints failed:"
    for endpoint in "${FAILED_ENDPOINTS[@]}"; do
        echo "${LOG_TAG}   - ${endpoint}"
    done
else
    echo "${LOG_TAG} All endpoints exported successfully."
fi

echo