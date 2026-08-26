#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# npm-import.sh
#
# Imports config/npm-config.json into Nginx Proxy Manager.
#
# Behaviour:
#
#   Certificate:
#     - Looks up existing certificate by nice_name (must already exist).
#     - Does NOT create or upload certificates.
#
#   Proxy hosts:
#     - Find by domain.
#     - Update if existing.
#     - Create if missing.
#
# Existing NPM objects that aren't in the configuration are NOT deleted.
#
# Required environment:
#
#   DOMAIN_NAME
#   IP_ADDRESS
#   NPM_EMAIL
#   NPM_PASSWORD
#
# Dependencies:
#
#   curl
#   jq
# ---------------------------------------------------------------------------

LOG_TAG="[npm-import]"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
CONFIG_FILE="${PROJECT_ROOT}/config/npm-config.json"

# ---------------------------------------------------------------------------
# Read .env
# ---------------------------------------------------------------------------

read_env_value() {
    local key="$1"
    local value=""

    if [[ -f "${ENV_FILE}" ]]; then
        value="$(
            grep -E "^${key}=" "${ENV_FILE}" |
            tail -n1 |
            cut -d '=' -f2- ||
            true
        )"

        value="${value%\"}"
        value="${value#\"}"

        value="${value%\'}"
        value="${value#\'}"
    fi

    echo "${value}"
}

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

if [[ -z "${DOMAIN_NAME:-}" ]]; then
    DOMAIN_NAME="$(read_env_value DOMAIN_NAME)"
fi

if [[ -z "${IP_ADDRESS:-}" ]]; then
    IP_ADDRESS="$(read_env_value IP_ADDRESS)"
fi

NPM_EMAIL="${NPM_EMAIL:-}"
NPM_PASSWORD="${NPM_PASSWORD:-}"

if [[ -z "${DOMAIN_NAME}" ]]; then
    echo "${LOG_TAG} ERROR: DOMAIN_NAME is not set."
    exit 1
fi

if [[ -z "${IP_ADDRESS}" ]]; then
    echo "${LOG_TAG} ERROR: IP_ADDRESS is not set."
    exit 1
fi

if [[ -z "${NPM_EMAIL}" || -z "${NPM_PASSWORD}" ]]; then
    echo "${LOG_TAG} ERROR: NPM_EMAIL and/or NPM_PASSWORD are not set."
    echo
    echo "${LOG_TAG} If they are in ~/.zshrc, run:"
    echo
    echo "    ./npm-import.sh"
    echo
    echo "${LOG_TAG} Or:"
    echo
    echo "    sudo --preserve-env=NPM_EMAIL,NPM_PASSWORD bash npm-import.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate config
# ---------------------------------------------------------------------------

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "${LOG_TAG} ERROR: Configuration file not found:"
    echo "${LOG_TAG} ${CONFIG_FILE}"
    echo
    echo "${LOG_TAG} Run generate-npm-config.sh first."
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

for command in curl jq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "${LOG_TAG} ERROR: '${command}' is required."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# NPM hosts
# ---------------------------------------------------------------------------

NPM_HOSTS=(
    "proxy.${DOMAIN_NAME}:81"
    "${IP_ADDRESS}:81"
)

# ---------------------------------------------------------------------------
# Authenticate
# ---------------------------------------------------------------------------

get_token() {
    local host="$1"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        -X POST \
        "http://${host}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "$(
            jq -n \
                --arg identity "${NPM_EMAIL}" \
                --arg secret "${NPM_PASSWORD}" \
                '{
                    identity: $identity,
                    secret: $secret
                }'
        )" |
        jq -r '.token // empty'
}

NPM_BASE_URL=""
NPM_TOKEN=""

for host in "${NPM_HOSTS[@]}"; do

    echo "${LOG_TAG} Trying ${host} ..."

    TOKEN="$(get_token "${host}" 2>/dev/null || true)"

    if [[ -z "${TOKEN}" ]]; then
        echo "${LOG_TAG} ${host}: authentication failed"
        continue
    fi

    echo "${LOG_TAG} ${host}: authenticated successfully"

    NPM_BASE_URL="${host}"
    NPM_TOKEN="${TOKEN}"

    break

done

if [[ -z "${NPM_BASE_URL}" ]]; then
    echo "${LOG_TAG} ERROR: Could not authenticate with NPM."
    exit 1
fi

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

npm_get() {
    local endpoint="$1"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X GET \
        "http://${NPM_BASE_URL}${endpoint}" \
        -H "Authorization: Bearer ${NPM_TOKEN}"
}

npm_post() {
    local endpoint="$1"
    local body="$2"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X POST \
        "http://${NPM_BASE_URL}${endpoint}" \
        -H "Authorization: Bearer ${NPM_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${body}"
}

npm_put() {
    local endpoint="$1"
    local body="$2"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X PUT \
        "http://${NPM_BASE_URL}${endpoint}" \
        -H "Authorization: Bearer ${NPM_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${body}"
}

# ---------------------------------------------------------------------------
# Certificate lookup
# ---------------------------------------------------------------------------

get_certificate_id_by_name() {
    local nice_name="$1"
    npm_get "/api/nginx/certificates" |
        jq -r \
            --arg name "${nice_name}" \
            '
            .[]
            | select(.nice_name == $name)
            | .id
            ' |
        head -n1
}

# The exact nice_name of the Let's Encrypt certificate in NPM
CERT_NICE_NAME="${DOMAIN_NAME}, *.${DOMAIN_NAME}"

echo
echo "${LOG_TAG} Looking up certificate: ${CERT_NICE_NAME}"

CERT_ID="$(get_certificate_id_by_name "${CERT_NICE_NAME}")"

if [[ -z "${CERT_ID}" ]]; then
    echo "${LOG_TAG} ERROR: Certificate '${CERT_NICE_NAME}' was not found in NPM."
    echo "${LOG_TAG} Please create it via the NPM UI (Let's Encrypt with DNS challenge) first."
    exit 1
fi

echo "${LOG_TAG} Found certificate ID: ${CERT_ID}"

# ---------------------------------------------------------------------------
# Proxy hosts
# ---------------------------------------------------------------------------

PROXY_COUNT="$(jq '.proxy_hosts // [] | length' "${CONFIG_FILE}")"

echo
echo "${LOG_TAG} ==============================================="
echo "${LOG_TAG} Proxy Hosts"
echo "${LOG_TAG} ==============================================="

for ((i = 0; i < PROXY_COUNT; i++)); do

    DOMAIN="$(
        jq -r ".proxy_hosts[${i}].domain_names[0]" "${CONFIG_FILE}"
    )"

    echo
    echo "${LOG_TAG} ${DOMAIN}"

    # Build NPM API payload: remove certificate_name and name, set certificate_id
    HOST_JSON="$(
        jq \
            --argjson index "${i}" \
            --arg cert_id "${CERT_ID}" \
            '
            .proxy_hosts[$index]
            |
            del(.certificate_name, .name)   # <-- FIX: delete both fields
            |
            .certificate_id = ($cert_id | tonumber)
            ' \
            "${CONFIG_FILE}"
    )"

    # Find existing host by domain
    HOST_ID="$(
        npm_get "/api/nginx/proxy-hosts" |
        jq -r \
            --arg domain "${DOMAIN}" \
            '
            .[]
            | select(
                (.domain_names // [])
                | index($domain)
            )
            | .id
            ' |
        head -n1
    )"

    if [[ -n "${HOST_ID}" ]]; then
        echo "${LOG_TAG} Existing host found: ID ${HOST_ID}"
        echo "${LOG_TAG} Updating..."
        npm_put "/api/nginx/proxy-hosts/${HOST_ID}" "${HOST_JSON}" >/dev/null
        echo "${LOG_TAG} ${DOMAIN}: updated successfully."
    else
        echo "${LOG_TAG} Host does not exist."
        echo "${LOG_TAG} Creating..."
        npm_post "/api/nginx/proxy-hosts" "${HOST_JSON}" >/dev/null
        echo "${LOG_TAG} ${DOMAIN}: created successfully."
    fi

done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "${LOG_TAG} ==============================================="
echo "${LOG_TAG} IMPORT COMPLETE"
echo "${LOG_TAG} ==============================================="
echo
echo "${LOG_TAG} Domain: ${DOMAIN_NAME}"
echo "${LOG_TAG} IP:     ${IP_ADDRESS}"
echo "${LOG_TAG} NPM:    ${NPM_BASE_URL}"
echo "${LOG_TAG} Certificate: ${CERT_NICE_NAME} (ID ${CERT_ID})"
echo
echo "${LOG_TAG} Proxy hosts processed: ${PROXY_COUNT}"
echo
echo "${LOG_TAG} Existing objects were updated."
echo "${LOG_TAG} Missing objects were created."
echo "${LOG_TAG} Nothing was deleted."
echo