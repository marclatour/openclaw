#!/usr/bin/env bash
# Run a Rundeck job and return the execution ID
# Usage: rundeck-run-job.sh <project> <group> <name> [options_json]
# Example: rundeck-run-job.sh my-project deploy prod '{"environment":"staging"}'

set -eo pipefail

PROJECT="$1"
GROUP="$2"
NAME="$3"
OPTIONS_JSON="${4:-{}}"

if [[ -z "$PROJECT" ]] || [[ -z "$NAME" ]]; then
    echo "Usage: $0 <project> <group> <name> [options_json]" >&2
    exit 1
fi

if [[ -z "${RUNDECK_URL:-}" ]] || [[ -z "${RUNDECK_API_TOKEN:-}" ]]; then
    echo "ERROR: RUNDECK_URL and RUNDECK_API_TOKEN must be set" >&2
    exit 1
fi

if ! echo "$OPTIONS_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: options_json must be a valid JSON object" >&2
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

# Fetch all jobs in project
JOBS=$(run_api "$RUNDECK_URL/api/43/project/$PROJECT/jobs" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json")

if echo "$JOBS" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$JOBS" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

if ! echo "$JOBS" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "API Error: expected jobs array response" >&2
    exit 1
fi

# Find job by group and name
JOB=$(echo "$JOBS" | jq --arg group "$GROUP" --arg name "$NAME" \
    '.[] | select((.group == $group or ($group == "" and (.group == "" or .group == null))) and .name == $name)')

if [[ -z "$JOB" ]] || [[ "$JOB" == "null" ]]; then
    echo "ERROR: Job not found: $PROJECT/$GROUP/$NAME" >&2
    exit 1
fi

JOB_ID=$(echo "$JOB" | jq -r '.id')

# Run the job
PAYLOAD=$(jq -n --argjson opts "$OPTIONS_JSON" '{options: $opts}')

RESPONSE=$(run_api -X POST "$RUNDECK_URL/api/43/job/$JOB_ID/run" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# Check for errors
if echo "$RESPONSE" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$RESPONSE" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

# Output execution info
echo "$RESPONSE" | jq '{
    executionId: .id,
    status: .status,
    jobName: .job.name,
    dateStarted: .dateStarted.date
}'
