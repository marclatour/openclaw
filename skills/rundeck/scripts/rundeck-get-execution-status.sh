#!/usr/bin/env bash
# Get execution status
# Usage: rundeck-get-execution-status.sh <execution_id>

set -eo pipefail

EXECUTION_ID="$1"

if [[ -z "$EXECUTION_ID" ]]; then
    echo "Usage: $0 <execution_id>" >&2
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

# Fetch execution status
STATUS=$(run_api "$RUNDECK_URL/api/43/execution/$EXECUTION_ID" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json")

# Check for errors
if echo "$STATUS" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$STATUS" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

# Output status
echo "$STATUS" | jq '{
    id: .id,
    status: .status,
    dateStarted: .dateStarted.date,
    dateEnded: .dateEnded.date,
    jobName: .job.name,
    jobGroup: .job.group,
    project: .job.project
}'
