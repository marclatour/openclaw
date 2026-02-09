# Output Templates

Standard output formats for rundeck commands.

**Table of Contents**
- [Job List](#job-list)
- [Job Description](#job-description)
- [Plan Summary](#plan-summary)
- [Execution Started](#execution-started)
- [Execution Status](#execution-status)
- [Execution Complete](#execution-complete)
- [Error Outputs](#error-outputs)

## Job List

```
## Jobs in {project} {group_filter}

| Alias | Description | Scheduled |
|-------|-------------|-----------|
| {project}/{group}/{name} | {description} | {yes/no} |

{count} jobs found. {warning if >50: "Showing first 50. Filter by group to narrow results."}
```

## Job Description

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

## Plan Summary

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

## Execution Started

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

## Execution Status

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

## Execution Complete

### Success
```
## Execution Succeeded

| Field | Value |
|-------|-------|
| Job | {alias} |
| Execution ID | {execution_id} |
| Duration | {duration} |
```

### Failure
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

## Error Outputs

### Authentication Error (401)
```
## Authentication Failed (401)

The Rundeck API token is invalid or expired. Check RUNDECK_API_TOKEN and try again.
Do not retry this request.
```

### Access Denied (403)
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

### Job Not Found (404)
```
## Job Not Found

Job not found: `{alias}`

Check the project, group, and name. Use `jobs [project]` to list available jobs.
```
