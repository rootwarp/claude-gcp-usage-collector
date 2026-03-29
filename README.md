# claude-gcp-usage-collector

Deploy an OpenTelemetry Collector on Google Cloud Run that receives Claude Code CLI usage metrics and forwards them to GCP Managed Prometheus.

## Architecture

```
Developer Mac (Claude Code CLI)
  → OTLP/gRPC push (port 443)
    → Cloud Run (otel/opentelemetry-collector-contrib:0.148.0)
      → googlemanagedprometheus exporter
        → GCP Managed Prometheus (Monarch)
```

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI installed and authenticated with project-level editor/owner permissions
- `grpcurl` (for smoke test: `brew install grpcurl`)

## Quickstart

```bash
# 1. Configure
cp .env.example .env
# Edit .env — set PROJECT_ID to your GCP project ID

# 2. Deploy
make deploy

# 3. Verify
make status
make test

# 4. Configure Claude Code (on each developer machine)
# Add to ~/.claude/settings.json — replace <COLLECTOR_URL> with the URL from make deploy
```

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

## Make Targets

| Target | Description |
|--------|-------------|
| `make deploy` | Full deploy: create SA, grant IAM, build image, deploy to Cloud Run |
| `make destroy` | Remove Cloud Run service and associated resources |
| `make status` | Show service URL, status, and instance count |
| `make test` | Send test OTLP payload and verify metrics in Cloud Monitoring |
| `make build` | Build and push container image only (no deploy) |
| `make logs` | Tail Cloud Run service logs |
| `make help` | Show available targets |

Pass variables via `.env` file or command line:

```bash
make deploy PROJECT_ID=my-project REGION=asia-northeast1
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PROJECT_ID` | Yes | — | GCP project ID |
| `REGION` | No | `us-central1` | Cloud Run deployment region |
| `SERVICE_NAME` | No | `otel-collector` | Cloud Run service name |
| `SA_NAME` | No | `otel-collector` | Service account name |

## Client Setup

See [docs/client-setup.md](docs/client-setup.md) for detailed developer onboarding instructions, optional settings, and available metrics.

## Image Version

The collector image is pinned to `otel/opentelemetry-collector-contrib:0.148.0`. To upgrade, update the tag in `Dockerfile` and run `make deploy`.

## License

MIT
