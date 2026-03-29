# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Deploy a stock OpenTelemetry Collector on Cloud Run that receives Claude Code CLI metrics (OTLP/gRPC) and forwards them to GCP Managed Prometheus. No custom application code — config, scripts, and docs only.

## Tech Stack

- OTel Collector: `otel/opentelemetry-collector-contrib:0.148.0` (pinned)
- Exporter: `googlemanagedprometheus`
- Infrastructure: Google Cloud Run (public, no auth, scale-to-zero)
- Deployment: Makefile + Bash scripts
- No Terraform, no CI/CD

## Key Commands

```bash
make deploy PROJECT_ID=<id>    # Full deploy: APIs → SA → build → Cloud Run
make destroy PROJECT_ID=<id>   # Teardown all resources
make status PROJECT_ID=<id>    # Show service URL, health, revisions
make test PROJECT_ID=<id>      # Smoke test: send metric, check Cloud Monitoring
make logs PROJECT_ID=<id>      # Tail Cloud Run logs
make build PROJECT_ID=<id>     # Build and push image only
make help                      # List all targets
```

## Architecture

Push-based pipeline, no pull/scrape:
```
Claude Code (Mac) → OTLP/gRPC :443 → Cloud Run OTel Collector → googlemanagedprometheus → GCP Managed Prometheus
```

## Conventions

- All GCP-specific values (project ID, region) via environment variables — never hardcoded
- Scripts use `set -euo pipefail` and validate required env vars with `${VAR:?msg}`
- Makefile loads `.env` if present and exports all vars to scripts
- Collector config uses `${env:...}` syntax for runtime values
- Image tag pinned in `Dockerfile` — update manually and redeploy to upgrade

## Key Files

- `otel-collector-config.yaml` — Collector pipeline (receiver → processors → exporter)
- `Dockerfile` — 3-line wrapper: COPY config into stock contrib image
- `Makefile` — User-facing interface, delegates to `scripts/`
- `scripts/deploy.sh` — Idempotent full deployment
- `scripts/destroy.sh` — Idempotent teardown
- `scripts/status.sh` — Service inspection
- `scripts/test.sh` — Smoke test via grpcurl
- `docs/client-setup.md` — Developer onboarding for Claude Code settings
