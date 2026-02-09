#!/usr/bin/env bash
# Get detailed information about a specific job
# Usage: rundeck-describe-job.sh <project> <group> <name>
# Group can be empty for jobs in root (use "")

set -eo pipefail

PROJECT="$1"
GROUP="$2"
NAME="$3"

if [[ -z "$PROJECT" ]] || [[ -z "$NAME" ]]; then
    echo "Usage: $0 <project> <group> <name>" >&2
    echo "Note: Use empty string \"\" for group if job is in root" >&2
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

# Fetch job details
DETAIL=$(run_api "$RUNDECK_URL/api/43/job/$JOB_ID" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json")

if echo "$DETAIL" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$DETAIL" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

# Fetch recent executions
EXECUTIONS_RAW=$(run_api "$RUNDECK_URL/api/43/job/$JOB_ID/executions?max=5" \
    -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
    -H "Accept: application/json")

if echo "$EXECUTIONS_RAW" | jq -e 'type == "object" and (.error == true or has("error"))' >/dev/null 2>&1; then
    echo "API Error: $(echo "$EXECUTIONS_RAW" | jq -r '.error.message // .message // "unknown error"')" >&2
    exit 1
fi

EXECUTIONS=$(echo "$EXECUTIONS_RAW" | jq '.executions // []')

# Combine and output
jq -n --argjson job "$DETAIL" --argjson executions "$EXECUTIONS" '{
    id: $job.id,
    name: $job.name,
    group: $job.group,
    description: $job.description,
    scheduled: $job.scheduled,
    options: [$job.options[]? | {name, description, required, defaultValue, values}],
    recentExecutions: $executions
}'
