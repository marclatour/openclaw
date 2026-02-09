# Rundeck API Patterns

Complete reference for Rundeck API v43 interactions.

**Table of Contents**
- [Environment Setup](#environment-setup)
- [Projects](#projects)
- [Jobs](#jobs)
- [Executions](#executions)
- [Error Handling](#error-handling)

## Environment Setup

Required environment variables:
```bash
export RUNDECK_URL="https://rundeck.example.com"
export RUNDECK_API_TOKEN="your-token"
```

Standard headers for all requests:
```bash
-H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
-H "Accept: application/json"
```

## Projects

### List Projects
```bash
curl -s "$RUNDECK_URL/api/43/projects" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '.[].name'
```

## Jobs

### List Jobs in a Project
```bash
curl -s "$RUNDECK_URL/api/43/project/{project}/jobs" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '.[] | {id, name, group, description, scheduled}'
```

### Get Job Detail
```bash
curl -s "$RUNDECK_URL/api/43/job/{job_id}" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '{name, group, description, options: [.options[]? | {name, description, required, defaultValue, values}]}'
```

## Executions

### Run Job
```bash
curl -s -X POST "$RUNDECK_URL/api/43/job/{job_id}/run" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"options": {"key": "value"}}'
```

Response: extract `.id` as the execution ID.

### Get Execution Status
```bash
curl -s "$RUNDECK_URL/api/43/execution/{execution_id}" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '{id, status, dateStarted: .dateStarted.date, dateEnded: .dateEnded.date, job: .job.name}'
```

### Get Execution Output (Poll)
```bash
curl -s "$RUNDECK_URL/api/43/execution/{execution_id}/output?offset={offset}&maxlines=200&format=json" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json"
```

Response fields:
- `.entries[].log` - log lines
- `.offset` - next poll offset
- `.completed` or `.execCompleted` - check if done

Poll loop: repeat with updated offset until `.completed == true` or `.execCompleted == true`. Wait 2-3 seconds between polls.

### List Recent Executions
```bash
curl -s "$RUNDECK_URL/api/43/job/{job_id}/executions?max=5" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '.executions[] | {id, status, dateStarted: .dateStarted.date, dateEnded: .dateEnded.date}'
```

### Abort Execution
```bash
curl -s -X POST "$RUNDECK_URL/api/43/execution/{execution_id}/abort" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json"
```

## Error Handling

### HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Continue |
| 401 | Unauthorized | Hard stop - token invalid or expired |
| 403 | Forbidden | Hard stop - token lacks permission |
| 404 | Not found | Report not found, do not guess alternatives |
| 5xx | Server error | May retry once after brief delay |

### API Error Response Format
```json
{
  "error": true,
  "message": "Error description",
  "errorCode": "api.error.code",
  "apiversion": 43
}
```

## Alias Resolution

An alias is `project/group/name`. To resolve to a Rundeck UUID:

1. Fetch all jobs for the project: `GET /api/43/project/{project}/jobs`
2. Match where `.group == "{group}"` and `.name == "{name}"`
3. Extract `.id` (the UUID — never show this to the user)
4. If group is empty, the alias uses double-slash: `project//name` — match `.group == ""` or `.group == null`
5. If no match: report "Job not found: `{alias}`". Never guess alternatives.
