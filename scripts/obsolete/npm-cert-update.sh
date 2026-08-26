#!/bin/bash
set -uo pipefail

# ---------------------------------------------------------------------------
# npm-cert-update.sh
#
# Uploads a renewed acme.sh certificate to Nginx Proxy Manager.
#
# The certificate is identified by its NPM "nice_name", NOT by a hardcoded
# certificate ID.
#
# ---------------------------------------------------------------------------

LOG_TAG="[npm-cert-update]"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CERTIFICATE_NICE_NAME="HOME NETWORK CERT"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"

# ---------------------------------------------------------------------------
# Read value from .env
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
# Domain
# ---------------------------------------------------------------------------

if [[ -z "${DOMAIN_NAME:-}" ]]; then
    DOMAIN_NAME="$(read_env_value DOMAIN_NAME)"
fi

if [[ -z "${DOMAIN_NAME:-}" ]]; then
    echo "${LOG_TAG} ERROR: DOMAIN_NAME is not set."
    echo "${LOG_TAG} Add DOMAIN_NAME to ${ENV_FILE} or export it."
    exit 1
fi

# ---------------------------------------------------------------------------
# IP address
# ---------------------------------------------------------------------------

if [[ -z "${IP_ADDRESS:-}" ]]; then
    IP_ADDRESS="$(read_env_value IP_ADDRESS)"
fi

if [[ -z "${IP_ADDRESS:-}" ]]; then
    echo "${LOG_TAG} ERROR: IP_ADDRESS is not set."
    echo "${LOG_TAG} Add IP_ADDRESS to ${ENV_FILE} or export it."
    exit 1
fi

# ---------------------------------------------------------------------------
# NPM hosts
# ---------------------------------------------------------------------------

NPM_HOSTS=(
    "proxy.${DOMAIN_NAME}:81"
    "${IP_ADDRESS}:81"
)

# ---------------------------------------------------------------------------
# Certificate files
# ---------------------------------------------------------------------------

CERT_DIR="${HOME}/.acme.sh/${DOMAIN_NAME}_ecc"

CERT_FILE="${CERT_DIR}/fullchain.cer"
KEY_FILE="${CERT_DIR}/${DOMAIN_NAME}.key"

# ---------------------------------------------------------------------------
# ntfy
# ---------------------------------------------------------------------------

NTFY_URL="${NTFY_URL:-https://ntfy.${DOMAIN_NAME}/home-alerts}"

# ---------------------------------------------------------------------------
# NPM credentials
# ---------------------------------------------------------------------------

NPM_EMAIL="${NPM_EMAIL:-}"
NPM_PASSWORD="${NPM_PASSWORD:-}"

if [[ -z "${NPM_EMAIL}" || -z "${NPM_PASSWORD}" ]]; then
    echo "${LOG_TAG} ERROR: NPM_EMAIL and/or NPM_PASSWORD are not set."
    echo
    echo "${LOG_TAG} Add them to ~/.zshrc or source an environment file."
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
# Validate certificate files
# ---------------------------------------------------------------------------

if [[ ! -f "${CERT_FILE}" ]]; then
    echo "${LOG_TAG} ERROR: Certificate file not found:"
    echo "${LOG_TAG} ${CERT_FILE}"
    exit 1
fi

if [[ ! -f "${KEY_FILE}" ]]; then
    echo "${LOG_TAG} ERROR: Certificate key not found:"
    echo "${LOG_TAG} ${KEY_FILE}"
    exit 1
fi

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
        )" |
        jq -r '.token // empty'
}

# ---------------------------------------------------------------------------
# Find certificate ID by Nice Name
# ---------------------------------------------------------------------------

get_certificate_id() {
    local base_url="$1"
    local token="$2"
    local nice_name="$3"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X GET \
        "http://${base_url}/api/nginx/certificates" \
        -H "Authorization: Bearer ${token}" |
        jq -r \
            --arg name "${nice_name}" \
            '
            .[]
            | select(.nice_name == $name)
            | .id
            ' |
        head -n1
}

# ---------------------------------------------------------------------------
# Upload certificate
# ---------------------------------------------------------------------------

upload_cert() {
    local base_url="$1"
    local token="$2"
    local certificate_id="$3"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -o /tmp/npm-cert-upload-response.json \
        -w "%{http_code}" \
        -X POST \
        "http://${base_url}/api/nginx/certificates/${certificate_id}/upload" \
        -H "Authorization: Bearer ${token}" \
        -F "certificate=@${CERT_FILE}" \
        -F "certificate_key=@${KEY_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "${LOG_TAG} Domain: ${DOMAIN_NAME}"
echo "${LOG_TAG} Certificate nice_name: ${CERTIFICATE_NICE_NAME}"
echo "${LOG_TAG} Certificate directory: ${CERT_DIR}"

success=0

for host in "${NPM_HOSTS[@]}"; do

    echo
    echo "${LOG_TAG} Trying ${host} ..."

    TOKEN="$(
        get_token "${host}" 2>/dev/null ||
        true
    )"

    if [[ -z "${TOKEN}" ]]; then
        echo "${LOG_TAG} ${host}: could not get auth token"
        echo "${LOG_TAG} trying next host"
        continue
    fi

    echo "${LOG_TAG} ${host}: authenticated successfully"

    echo "${LOG_TAG} Looking up certificate '${CERTIFICATE_NICE_NAME}'..."

    CERT_ID="$(
        get_certificate_id \
            "${host}" \
            "${TOKEN}" \
            "${CERTIFICATE_NICE_NAME}" \
            2>/dev/null ||
        true
    )"

    if [[ -z "${CERT_ID}" ]]; then
        echo "${LOG_TAG} ${host}: certificate '${CERTIFICATE_NICE_NAME}' was not found"
        echo "${LOG_TAG} trying next host"
        continue
    fi

    echo "${LOG_TAG} ${host}: certificate found with ID ${CERT_ID}"

    echo "${LOG_TAG} Uploading renewed certificate..."

    STATUS="$(
        upload_cert \
            "${host}" \
            "${TOKEN}" \
            "${CERT_ID}"
    )"

    if [[ "${STATUS}" == "200" ]]; then

        echo "${LOG_TAG} ${host}: certificate uploaded successfully"

        success=1
        break

    else

        echo "${LOG_TAG} ${host}: upload failed (HTTP ${STATUS})"
        echo "${LOG_TAG} Response:"

        cat /tmp/npm-cert-upload-response.json 2>/dev/null || true

        echo
        echo "${LOG_TAG} trying next host"

    fi

done

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

rm -f /tmp/npm-cert-upload-response.json

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

if [[ "${success}" -ne 1 ]]; then

    echo
    echo "${LOG_TAG} ERROR: all NPM hosts failed."
    echo "${LOG_TAG} Certificate was NOT uploaded to NPM."

    exit 1

fi

# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------

echo
echo "${LOG_TAG} Certificate renewal completed successfully."

curl \
    -s \
    -o /dev/null \
    --max-time 10 \
    -d "Certificate renewed for $(hostname)" \
    "${NTFY_URL}" \
    || true

echo "${LOG_TAG} Done."