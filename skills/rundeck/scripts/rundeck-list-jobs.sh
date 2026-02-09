#!/usr/bin/env bash
# List jobs in a Rundeck project, optionally filtered by group
# Usage: rundeck-list-jobs.sh <project> [group]

set -eo pipefail

PROJECT="$1"
GROUP_FILTER="${2:-}"

if [[ -z "$PROJECT" ]]; then
    echo "Usage: $0 <project> [group]" >&2
    exit 1
fi

if [[ -z "${RUNDECK_URL:-}" ]] || [[ -z "${RUNDECK_API_TOKEN:-}" ]]; then
    echo "ERROR: RUNDECK_URL and RUNDECK_API_TOKEN must be set" >&2
    exit 1
fi

api_error_message() {
    local payload="${1:-}"
    local message
    message=$(echo "$payload" | jq -r 'if type == "object" then .error.message // .message // empty else empty end' 2>/dev/null || true)
    if [[ -n "$message" ]]; then
        echo "$message"
    elif [[ -n "$payload" ]]; then
        echo "$payload"
    else
        echo "request failed"
    fi
}

run_api() {
    local response
    if ! response=$(curl -sS --fail-with-body "$@" 2>&1); then
        echo "API Error: $(api_error_message "$response")" >&2
        return 1
    fi
    echo "$response"
}

# Fetch jobs
JOBS=$(run_api "$RUNDECK_URL/api/43/project/$PROJECT/jobs" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json")

# Check for API errors (Rundeck error payloads are objects, successful list is an array)
if echo "$JOBS" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$JOBS" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

if ! echo "$JOBS" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "API Error: expected jobs array response" >&2
    exit 1
fi

# Filter by group if specified
if [[ -n "$GROUP_FILTER" ]]; then
    echo "$JOBS" | jq --arg group "$GROUP_FILTER" '[.[] | select(.group == $group)]'
else
    echo "$JOBS"
fi
