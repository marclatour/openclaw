#!/usr/bin/env bash
# Tail execution output until completion
# Usage: rundeck-tail-execution.sh <execution_id> [--follow]
# Use --follow to keep polling until completion (default: output once)

set -eo pipefail

EXECUTION_ID="$1"
FOLLOW="${2:-}"

if [[ -z "$EXECUTION_ID" ]]; then
    echo "Usage: $0 <execution_id> [--follow]" >&2
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

OFFSET=0
COMPLETED=false

while [[ "$COMPLETED" == "false" ]]; do
    # Fetch output
    OUTPUT=$(run_api "$RUNDECK_URL/api/43/execution/$EXECUTION_ID/output?offset=$OFFSET&maxlines=200&format=json" \
        -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
        -H "Accept: application/json")
    
    # Check for errors
    if echo "$OUTPUT" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
        echo "API Error: $(echo "$OUTPUT" | jq -r '.error.message // .message // "unknown error"')" >&2
        exit 1
    fi
    
    # Print log entries
    echo "$OUTPUT" | jq -r '.entries[]?.log // empty'
    
    # Check completion
    COMPLETED=$(echo "$OUTPUT" | jq -r '.completed // .execCompleted // false')
    OFFSET=$(echo "$OUTPUT" | jq -r --argjson current_offset "$OFFSET" '.offset // ($current_offset + 200)')
    
    if [[ "$FOLLOW" != "--follow" ]]; then
        break
    fi
    
    if [[ "$COMPLETED" != "true" ]]; then
        sleep 2
    fi
done

# Output final status if following
if [[ "$FOLLOW" == "--follow" ]]; then
    STATUS_JSON=$(run_api "$RUNDECK_URL/api/43/execution/$EXECUTION_ID" \
        -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
        -H "Accept: application/json")
    if echo "$STATUS_JSON" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
        echo "API Error: $(echo "$STATUS_JSON" | jq -r '.error.message // .message // "unknown error"')" >&2
        exit 1
    fi
    STATUS=$(echo "$STATUS_JSON" | jq -r '.status')
    echo ""
    echo "Execution $EXECUTION_ID completed with status: $STATUS"
fi
