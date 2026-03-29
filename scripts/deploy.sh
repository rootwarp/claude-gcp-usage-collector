#!/usr/bin/env bash
set -euo pipefail

# Validate required environment variables
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${REGION:?REGION is required}"
: "${SERVICE_NAME:?SERVICE_NAME is required}"
: "${SA_NAME:?SA_NAME is required}"
: "${SA_EMAIL:?SA_EMAIL is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

# Step 1: Enable required APIs
echo "Enabling required APIs..."
gcloud services enable \
  run.googleapis.com \
  monitoring.googleapis.com \
  cloudbuild.googleapis.com \
  --project "${PROJECT_ID}"

# Step 2: Create service account (skip if exists)
echo "Setting up service account..."
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project "${PROJECT_ID}" &>/dev/null; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name "OTel Collector Service Account" \
    --project "${PROJECT_ID}"
  echo "Service account created: ${SA_EMAIL}"
else
  echo "Service account already exists: ${SA_EMAIL}"
fi

# Step 3: Grant monitoring.metricWriter role
echo "Granting IAM role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/monitoring.metricWriter" \
  --condition=None \
  --quiet

# Step 4: Build and push image
echo "Building container image..."
gcloud builds submit \
  --tag "${IMAGE_TAG}" \
  --project "${PROJECT_ID}"

# Step 5: Deploy to Cloud Run
echo "Deploying to Cloud Run..."
gcloud run deploy "${SERVICE_NAME}" \
  --image "${IMAGE_TAG}" \
  --region "${REGION}" \
  --port 4317 \
  --use-http2 \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 2 \
  --allow-unauthenticated \
  --service-account "${SA_EMAIL}" \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID},GOOGLE_CLOUD_REGION=${REGION}" \
  --project "${PROJECT_ID}"

# Step 6: Print service URL
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --format 'value(status.url)')

echo ""
echo "Collector deployed: ${SERVICE_URL}"
echo ""
echo "Configure Claude Code with:"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT=${SERVICE_URL}:443"
