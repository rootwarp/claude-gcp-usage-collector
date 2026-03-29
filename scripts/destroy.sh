#!/usr/bin/env bash
set -euo pipefail

# Validate required environment variables
: "${PROJECT_ID:?PROJECT_ID is required}"
: "${REGION:?REGION is required}"
: "${SERVICE_NAME:?SERVICE_NAME is required}"
: "${SA_EMAIL:?SA_EMAIL is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

# Step 1: Delete Cloud Run service
echo "Deleting Cloud Run service..."
gcloud run services delete "${SERVICE_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --quiet 2>/dev/null || true

# Step 2: Remove IAM binding
echo "Removing IAM binding..."
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/monitoring.metricWriter" \
  --quiet 2>/dev/null || true

# Step 3: Delete service account
echo "Deleting service account..."
gcloud iam service-accounts delete "${SA_EMAIL}" \
  --project "${PROJECT_ID}" \
  --quiet 2>/dev/null || true

# Step 4: Delete container image
echo "Deleting container image..."
gcloud container images delete "${IMAGE_TAG}" \
  --force-delete-tags \
  --project "${PROJECT_ID}" \
  --quiet 2>/dev/null || true

echo "All resources deleted."
