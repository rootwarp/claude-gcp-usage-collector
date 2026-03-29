#!/usr/bin/env bash
set -euo pipefail

# Check for required tools
if ! command -v grpcurl &>/dev/null; then
  echo "Error: grpcurl is not installed."
  echo "Install it with: brew install grpcurl"
  exit 1
fi

if ! command -v gcloud &>/dev/null; then
  echo "Error: gcloud CLI is not installed."
  echo "Install it from: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Validate required environment variables
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${REGION:?REGION is required}"
: "${SERVICE_NAME:?SERVICE_NAME is required}"

# Retrieve the Cloud Run service URL
echo "Retrieving service URL..."
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format 'value(status.url)')

if [[ -z "${SERVICE_URL}" ]]; then
  echo "Error: Could not retrieve service URL. Is the service deployed?"
  exit 1
fi

echo "Sending test metric to ${SERVICE_URL}..."

TIMESTAMP="$(date +%s)000000000"

# Send a valid OTLP ExportMetricsServiceRequest via grpcurl using server reflection.
# The OTel Collector gRPC receiver supports reflection in contrib builds.
grpcurl \
  -d '{
    "resource_metrics": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"string_value": "smoke-test"}
        }]
      },
      "scope_metrics": [{
        "metrics": [{
          "name": "test.metric",
          "gauge": {
            "data_points": [{
              "as_int": "1",
              "time_unix_nano": "'"${TIMESTAMP}"'"
            }]
          }
        }]
      }]
    }]
  }' \
  "${SERVICE_URL#https://}:443" \
  opentelemetry.proto.collector.metrics.v1.MetricsService/Export

echo ""
echo "Test metric sent successfully!"
echo ""
echo "Check Cloud Monitoring in ~60s:"
echo "  Console: https://console.cloud.google.com/monitoring/metrics-explorer?project=${PROJECT_ID}"
echo ""
echo "Look for the metric 'test_metric' (dots are converted to underscores)."
echo "Use PromQL: test_metric"
