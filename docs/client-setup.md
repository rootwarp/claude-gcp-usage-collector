# Client Setup: Configuring Claude Code to Push Metrics

This guide explains how to configure your local Claude Code CLI to push usage metrics to the team's OTel Collector on Cloud Run.

## Prerequisites

- The collector must be deployed (`make deploy`) and you need the service URL from the deploy output
- Claude Code CLI installed on your machine

## Required Configuration

Add the following to `~/.claude/settings.json`. Replace `<COLLECTOR_URL>` with the Cloud Run service URL from `make deploy` output (e.g., `otel-collector-abc123-uc.a.run.app`):

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://<COLLECTOR_URL>:443"
  }
}
```

**Endpoint URL format**: Provide only the base URL with port 443. Claude Code automatically handles the gRPC service path — do not append `/v1/metrics` or any trailing path.

## Optional Settings

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://<COLLECTOR_URL>:443",
    "OTEL_METRIC_EXPORT_INTERVAL": "60000",
    "OTEL_METRICS_INCLUDE_SESSION_ID": "false",
    "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "true"
  }
}
```

| Setting | Default | Recommendation | Rationale |
|---------|---------|----------------|-----------|
| `OTEL_METRIC_EXPORT_INTERVAL` | `60000` (60s) | Keep default | Sufficient for usage metrics; lower values increase GMP cost |
| `OTEL_METRICS_INCLUDE_SESSION_ID` | `true` | `false` | Reduces cardinality significantly; session-level granularity is rarely needed for team dashboards |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` | `true` | `true` | Required for per-developer usage breakdowns |

## Settings File Locations

Claude Code reads settings from multiple locations with the following precedence:

| Location | Purpose | Precedence |
|----------|---------|------------|
| `~/.claude/settings.json` | Per-user settings | User-level |
| `.claude/settings.json` (in project) | Per-project settings | Project-level |
| `/Library/Application Support/ClaudeCode/managed-settings.json` | MDM-managed org settings | Highest (cannot be overridden) |

For team-wide deployment, use the per-user settings file (`~/.claude/settings.json`) on each developer machine.

## Available Metrics

Claude Code emits the following metrics. The `googlemanagedprometheus` exporter converts dots (`.`) to underscores (`_`) in metric names.

| Metric | PromQL Name | Type | Key Attributes |
|--------|-------------|------|---------------|
| `claude_code.token.usage` | `claude_code_token_usage` | Counter | `type` (input/output/cacheRead/cacheCreation), `model` |
| `claude_code.cost.usage` | `claude_code_cost_usage` | Counter | `model` |
| `claude_code.session.count` | `claude_code_session_count` | Counter | -- |
| `claude_code.lines_of_code.count` | `claude_code_lines_of_code_count` | Counter | `type` (added/removed) |
| `claude_code.commit.count` | `claude_code_commit_count` | Counter | -- |
| `claude_code.pull_request.count` | `claude_code_pull_request_count` | Counter | -- |
| `claude_code.active_time.total` | `claude_code_active_time_total` | Counter | `type` (user/cli) |
| `claude_code.code_edit_tool.decision` | `claude_code_code_edit_tool_decision` | Counter | `tool_name`, `decision` |

## Sample PromQL Queries

Use these in Cloud Monitoring's Metrics Explorer or a connected Grafana instance.

```promql
# Total token usage across all developers (last 24h)
sum(rate(claude_code_token_usage[24h]))

# Token usage by model
sum by (model) (rate(claude_code_token_usage[1h]))

# Cost per developer (last 7d)
sum by (user_account_uuid) (increase(claude_code_cost_usage[7d]))

# Active sessions (last hour)
sum(rate(claude_code_session_count[1h]))

# Lines of code added vs removed (last 24h)
sum by (type) (rate(claude_code_lines_of_code_count[24h]))

# Input vs output tokens by model
sum by (type, model) (rate(claude_code_token_usage[1h]))
```

## Verifying Your Setup

After configuring your settings:

1. Start a Claude Code session and perform some work (ask questions, edit files)
2. Wait at least 60 seconds for the export interval
3. Check Cloud Monitoring:
   ```
   https://console.cloud.google.com/monitoring/metrics-explorer?project=<PROJECT_ID>
   ```
4. Search for `claude_code_token_usage` in the metric selector

Alternatively, run `make test` from the repo to send a synthetic test metric and verify the pipeline end-to-end.
