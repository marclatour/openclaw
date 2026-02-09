---
name: runbot-rundeck
description: "Run and monitor Rundeck jobs. Use when asked to list, describe, plan, run, check status, or tail output of Rundeck automation jobs. Supports alias-driven execution, risk-based confirmation, and automatic output tailing. Triggers: rundeck, runbot, runbook, orchestrate, deploy, restart, diagnose, job status."
metadata:
  {
    "openclaw":
      {
        "emoji": "🔧",
        "primaryEnv": "RUNDECK_API_TOKEN",
        "requires": { "env": ["RUNDECK_URL", "RUNDECK_API_TOKEN"], "bins": ["curl", "jq"] },
      },
  }
---

# Rundeck Job Runner

Trigger and monitor Rundeck jobs via API using alias-driven execution with risk-based confirmation.

## Setup

Set these environment variables:

```bash
export RUNDECK_URL="https://rundeck.example.com"    # Base URL, no trailing slash
export RUNDECK_API_TOKEN="your-acl-scoped-token"     # Token must be ACL-scoped
```

The token's ACL determines which projects and jobs are visible. No additional allowlisting is needed.

## Core Rules

1. **Read-only default posture.** Never execute a job without explicit user confirmation.
2. **Alias-only interface.** Always refer to jobs by `project/group/name` alias. Never expose UUIDs to the user.
3. **Confirmation required before any `run`.** See Confirmation Workflow below.
4. **Never guess.** Do not invent aliases, fabricate job names, or suggest jobs that don't exist in the API response.
5. **Never bypass ACLs.** Do not retry after 401/403. These are hard stops.
6. **Redact secrets.** Mask sensitive option values in all output. See Redaction Rules below.
7. **Automatic output tailing.** After triggering a job, poll execution output until completion.

## API Patterns

All requests use API version 43 by default. Fallback to older API versions only if required by the target Rundeck instance. Common headers:

```bash
-H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
-H "Accept: application/json"
```

### List Projects

```bash
curl -s "$RUNDECK_URL/api/43/projects" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '.[].name'
```

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

Response fields: `.entries[].log` for log lines, `.offset` for next poll offset, `.completed` to check if done.
Poll loop: repeat with updated offset until `.completed == true` or `.execCompleted == true`. Wait 2-3 seconds between polls.

### List Recent Executions

```bash
curl -s "$RUNDECK_URL/api/43/job/{job_id}/executions?max=5" \
  -H "X-Rundeck-Auth-Token: $RUNDECK_API_TOKEN" \
  -H "Accept: application/json" | jq '.executions[] | {id, status, dateStarted: .dateStarted.date, dateEnded: .dateEnded.date}'
```

## Alias Resolution

An alias is `project/group/name`. To resolve to a Rundeck UUID:

1. Fetch all jobs for the project: `GET /api/43/project/{project}/jobs`
2. Match where `.group == "{group}"` and `.name == "{name}"`
3. Extract `.id` (the UUID — never show this to the user)
4. If group is empty, the alias uses double-slash: `project//name` — match `.group == ""` or `.group == null`
5. If no match: report "Job not found: `{alias}`". Never guess alternatives.

## Commands

### `jobs [project] [group]`

List available jobs, optionally filtered by project and/or group.

**Procedure:**

1. If no project specified, list projects first, then ask which one.
2. Fetch jobs for the project. If group specified, filter by group.
3. Render job list table.

### `describe <alias>`

Show job details, options schema, and recent executions.

**Procedure:**

1. Resolve alias to UUID.
2. Fetch job detail (options schema).
3. Fetch last 5 executions.
4. Render job description.

### `plan <alias> [key=value ...]`

Dry-run preview — show what would happen without executing.

**Procedure:**

1. Resolve alias to UUID.
2. Fetch job detail for options schema.
3. Validate provided options against the job's options schema.
4. Determine confirmation tier (see Confirmation Workflow).
5. Render plan summary with confirmation phrase.

### `run <alias> [key=value ...]`

Execute a job: plan, confirm, execute, and tail output.

**Procedure:**

1. Run the full `plan` procedure first.
2. Wait for user to provide the exact confirmation phrase.
3. Reject ambiguous confirmations ("yes", "ok", "go", "do it", "sure").
4. POST to run the job. Extract execution ID.
5. Render "Execution Started" output.
6. Automatically poll execution output until complete.
7. On success: render success output.
8. On failure: render failure output.

### `status <execution_id>`

Check the current state of an execution.

**Procedure:**

1. Fetch execution status.
2. Render status output.

### `tail <execution_id>`

Resume watching output of a running or completed execution.

**Procedure:**

1. Poll execution output from offset 0.
2. Stream log lines until complete.

### `help`

Show a summary of available commands.

## Output Templates

### Job List

```
## Jobs in {project} {group_filter}

| Alias | Description | Scheduled |
|-------|-------------|-----------|
| {project}/{group}/{name} | {description} | {yes/no} |

{count} jobs found. {warning if >50: "Showing first 50. Filter by group to narrow results."}
```

### Job Description

```
## {alias}

{description}

| Field | Value |
|-------|-------|
| Scheduled | {yes/no} |

### Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| {name} | {yes/no} | {default} | {description} |

### Recent Executions

| ID | Status | Started | Ended |
|----|--------|---------|-------|
| {execution_id} | {status} | {dateStarted} | {dateEnded} |
```

### Plan Summary

```
## Execution Plan

| Field | Value |
|-------|-------|
| Job | {alias} |

### Options (redacted)

| Option | Value |
|--------|-------|
| {key} | {value or [REDACTED]} |

{validation_errors if any}

### Confirm

To execute, reply with exactly:
> `CONFIRM run {alias} {key=value ...}`
{if tier 3: "Append `--risk-accepted` to acknowledge high risk."}
```

### Execution Started

```
## Execution Started

| Field | Value |
|-------|-------|
| Job | {alias} |
| Execution ID | {execution_id} |
| Started | {timestamp} |
| Options | {redacted key=value pairs} |

Tailing output...
```

### Status Update

```
## Execution Status

| Field | Value |
|-------|-------|
| Job | {alias} |
| Execution ID | {execution_id} |
| Status | {running/succeeded/failed/aborted} |
| Started | {dateStarted} |
| Ended | {dateEnded or "—"} |
```

### Execution Complete — Success

```
## Execution Succeeded

| Field | Value |
|-------|-------|
| Job | {alias} |
| Execution ID | {execution_id} |
| Duration | {duration} |
```

### Execution Complete — Failure

```
## Execution Failed

| Field | Value |
|-------|-------|
| Job | {alias} |
| Execution ID | {execution_id} |
| Status | failed |

### Last 50 Lines

{truncated log output}
```

### Auth Error (401)

```
## Authentication Failed (401)

The Rundeck API token is invalid or expired. Check RUNDECK_API_TOKEN and try again.
Do not retry this request.
```

### Auth Error (403)

```
## Access Denied (403)

The Rundeck API token does not have permission for this operation.
Contact your Rundeck operator to request access. Do not retry this request.
```

### Validation Error

```
## Validation Error

The following options failed validation:

- **{option}**: {error_message} (expected: {pattern or allowed_values})

Fix the options and try again.
```

## Confirmation Workflow

Three tiers based on the job and environment context. All jobs require confirmation.

**Tier 1 — Low risk, non-production:** Read-only or diagnostic jobs (health checks, log rotation) in non-prod environments.

**Tier 2 — Medium risk or production-adjacent:** State-changing jobs (restarts, deploys, backups) targeting staging/pre-prod.

**Tier 3 — High risk or production:** Production deployments, rollbacks, destructive operations, or any job where `environment=prod`/`environment=production`.

### Confirmation Phrases

Tiers 1 and 2 — user must reply with exactly:

```
CONFIRM run {alias} {key=value ...}
```

Tier 3 — user must append `--risk-accepted`:

```
CONFIRM run {alias} {key=value ...} --risk-accepted
```

### Confirmation Rules

- **Ambiguous confirmations are INVALID.** Reject: "yes", "ok", "go", "do it", "sure", "proceed", "confirm", "y", "yep", "yeah", or any variation.
- **Option changes invalidate confirmation.** If options change after seeing the plan, re-run the plan and require a new confirmation.
- **Cancellation:** `CONFIRM cancel {execution_id}` → `POST /api/43/execution/{execution_id}/abort`

## Redaction Rules

Redact sensitive values in all output (plan summaries, execution logs, status reports).

**Redact option values whose key (case-insensitive) contains:** `password`, `secret`, `token`, `api_key`, `credential`, `auth`, `passphrase`, `private`, or `key` when part of a compound like `ssh_key`/`access_key` (not `key_name`/`keyboard`).

**Redact values matching these patterns regardless of key:** strings starting with `Bearer `/ `Basic `, hex strings >32 chars, base64 strings >40 chars.

**In log lines, redact the value portion of:** `export VAR=value`, `password=value`, `token=value`, `secret=value`, or any `KEY=value` where KEY matches the rules above.

Display as `[REDACTED]`. When in doubt, redact — false positives are acceptable.

## ACL and Error Handling

- **401:** Hard stop. "Token is invalid or expired. Check `RUNDECK_API_TOKEN`." Do not retry.
- **403:** Hard stop. "Token does not have permission. Contact your Rundeck operator." Do not retry.
- **404:** Report not found. Do not guess alternatives.
- Never retry a privileged action (run, abort) after any auth failure.
- If a job listing succeeds but a specific job returns 403, report it per-job — do not fail the entire listing.

## Prohibited Operations

These Rundeck API endpoints are **forbidden**:

- `/api/43/project/{project}/run/command` — ad-hoc command execution
- `/api/43/project/{project}/run/script` — ad-hoc script execution
- `/api/43/project/{project}/run/url` — ad-hoc URL script execution
- `/api/43/system/executions/enable` or `/disable` — system execution toggle
- `/api/43/storage/keys/*` — key storage access
- Any SSH, SCP, or direct shell commands to Rundeck hosts

Only pre-defined Rundeck jobs can be executed through this skill.

## Audit and Limits

Every `run` must log: alias, redacted options, execution ID, user, timestamp (ISO 8601), and the exact confirmation phrase used. For Tier 3, echo the full confirmation phrase (including `--risk-accepted`) in output.

**Output limits:** Max 200 lines per poll batch. Failure summaries show last 50 lines. Job listings warn at >50 jobs and suggest filtering by group.
