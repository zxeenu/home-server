#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# generate-npm-config.sh
#
# Generates a deterministic Nginx Proxy Manager configuration from .env.
#
# Input:
#   <project-root>/.env
#
# Output:
#   <project-root>/config/npm-config.json
#
# The generated JSON is intentionally NOT source controlled.
# ---------------------------------------------------------------------------

LOG_TAG="[npm-config]"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${PROJECT_ROOT}/.env"
CONFIG_DIR="${PROJECT_ROOT}/config"
OUTPUT_FILE="${CONFIG_DIR}/npm-config.json"

mkdir -p "${CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Read values from .env
# ---------------------------------------------------------------------------

read_env_value() {
    local key="$1"

    if [[ ! -f "${ENV_FILE}" ]]; then
        return 0
    fi

    grep -E "^${key}=" "${ENV_FILE}" |
        tail -n1 |
        cut -d '=' -f2- |
        sed \
            -e 's/^"//' \
            -e 's/"$//' \
            -e "s/^'//" \
            -e "s/'$//"
}

DOMAIN_NAME="${DOMAIN_NAME:-$(read_env_value DOMAIN_NAME)}"
IP_ADDRESS="${IP_ADDRESS:-$(read_env_value IP_ADDRESS)}"

if [[ -z "${DOMAIN_NAME}" ]]; then
    echo "${LOG_TAG} ERROR: DOMAIN_NAME is not set."
    echo "${LOG_TAG} Add DOMAIN_NAME to ${ENV_FILE}."
    exit 1
fi

if [[ -z "${IP_ADDRESS}" ]]; then
    echo "${LOG_TAG} ERROR: IP_ADDRESS is not set."
    echo "${LOG_TAG} Add IP_ADDRESS to ${ENV_FILE}."
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "${LOG_TAG} ERROR: jq is required."
    exit 1
fi

echo "${LOG_TAG} DOMAIN_NAME=${DOMAIN_NAME}"
echo "${LOG_TAG} IP_ADDRESS=${IP_ADDRESS}"
echo "${LOG_TAG} Generating:"
echo "${LOG_TAG} ${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Generate JSON
# ---------------------------------------------------------------------------

jq -n \
    --arg domain "${DOMAIN_NAME}" \
    --arg ip "${IP_ADDRESS}" \
'
{
  version: 1,

  exported_at: (now | todateiso8601),

  domain_name: $domain,

  proxy_hosts: [

    {
      name: "books",
      domain_names: ["books." + $domain],
      forward_host: calibreweb,
      forward_port: 8083,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "proxy_buffer_size 128k;\nproxy_buffers 4 256k;\nproxy_busy_buffers_size 256k;",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "home",
      domain_names: ["home." + $domain],
      forward_host: "homepage",
      forward_port: 80,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: false,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "ntfy",
      domain_names: ["ntfy." + $domain],
      forward_host: $ip,
      forward_port: 8084,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "pdf",
      domain_names: ["pdf." + $domain],
      forward_host: "stirlingpdf",
      forward_port: 8080,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "pihole",
      domain_names: ["pihole." + $domain],
      forward_host: "pihole",
      forward_port: 80,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: false,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "plex",
      domain_names: ["plex." + $domain],
      forward_host: $ip,
      forward_port: 32400,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "portainer",
      domain_names: ["portainer." + $domain],
      forward_host: "portainer",
      forward_port: 9000,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "proxy",
      domain_names: ["proxy." + $domain],
      forward_host: "nginxproxymanager",
      forward_port: 81,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: false,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    },

    {
      name: "torrent",
      domain_names: ["torrent." + $domain],
      forward_host: "qbittorrent",
      forward_port: 8080,
      access_list_id: 0,
      certificate_name: "HOME NETWORK CERT",
      ssl_forced: true,
      caching_enabled: false,
      block_exploits: false,
      advanced_config: "",
      allow_websocket_upgrade: true,
      http2_support: false,
      forward_scheme: "http",
      enabled: true,
      locations: [],
      hsts_enabled: false,
      hsts_subdomains: false,
      trust_forwarded_proto: false
    }
  ],

  redirection_hosts: [],
  dead_hosts: [],
  streams: [],
  access_lists: [],

  certificates: [
    {
      name: "HOME NETWORK CERT",
      provider: "other",
      domain_names: [$domain]
    }
  ],

  settings: [
    {
      id: "default-site",
      value: "congratulations"
    }
  ]
}
' > "${OUTPUT_FILE}"

# ---------------------------------------------------------------------------
# Validate output
# ---------------------------------------------------------------------------

if ! jq empty "${OUTPUT_FILE}" >/dev/null 2>&1; then
    echo "${LOG_TAG} ERROR: Generated JSON is invalid."
    rm -f "${OUTPUT_FILE}"
    exit 1
fi

echo
echo "${LOG_TAG} Configuration generated successfully."
echo "${LOG_TAG} Output: ${OUTPUT_FILE}"
echo

jq '{
  domain_name,
  certificate: .certificates[0],
  proxy_hosts: [.proxy_hosts[] | {
    domain: .domain_names[0],
    forward_host,
    forward_port
  }]
}' "${OUTPUT_FILE}"