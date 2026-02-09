#!/usr/bin/env bash
# Validate Rundeck environment and dependencies

set -eo pipefail

ERRORS=0

# Check required environment variables
if [[ -z "${RUNDECK_URL:-}" ]]; then
    echo "ERROR: RUNDECK_URL is not set" >&2
    ERRORS=$((ERRORS + 1))
fi

if [[ -z "${RUNDECK_API_TOKEN:-}" ]]; then
    echo "ERROR: RUNDECK_API_TOKEN is not set" >&2
    ERRORS=$((ERRORS + 1))
fi

# Check dependencies
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is not installed" >&2
    ERRORS=$((ERRORS + 1))
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed" >&2
    ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi

# Test connectivity to Rundeck
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$RUNDECK_URL/api/43/system/info" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    200)
        echo "OK: Connected to Rundeck at $RUNDECK_URL"
        exit 0
        ;;
    401)
        echo "ERROR: Authentication failed (401) - check RUNDECK_API_TOKEN" >&2
        exit 1
        ;;
    403)
        echo "ERROR: Access denied (403) - token lacks permission" >&2
        exit 1
        ;;
    000)
        echo "ERROR: Cannot connect to $RUNDECK_URL - check URL and network" >&2
        exit 1
        ;;
    *)
        echo "ERROR: Unexpected HTTP response: $HTTP_CODE" >&2
        exit 1
        ;;
esac
