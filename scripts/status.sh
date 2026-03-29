#!/usr/bin/env bash
set -euo pipefail

# Validate required environment variables
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${REGION:?REGION is required}"
: "${SERVICE_NAME:?SERVICE_NAME is required}"

echo "=== Cloud Run Service ==="
gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format "table(
    status.url,
    status.conditions[0].status,
    spec.template.spec.containerConcurrency,
    spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],
    spec.template.metadata.annotations['autoscaling.knative.dev/maxScale']
  )"

echo ""
echo "=== Active Revisions ==="
gcloud run revisions list \
  --service "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format "table(metadata.name, status.conditions[0].status, spec.containers[0].image)"
