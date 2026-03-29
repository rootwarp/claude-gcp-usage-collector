# Load .env file if present
-include .env
export

# Required variables (pass via env or command line)
PROJECT_ID   ?=
REGION       ?= us-central1
SERVICE_NAME ?= otel-collector
SA_NAME      ?= otel-collector

# Derived
IMAGE_TAG    = gcr.io/$(PROJECT_ID)/$(SERVICE_NAME)
SA_EMAIL     = $(SA_NAME)@$(PROJECT_ID).iam.gserviceaccount.com

# Guard: require PROJECT_ID for targets that need it
guard-project-id:
ifndef PROJECT_ID
	$(error PROJECT_ID is required. Set in .env or pass via command line)
endif

.PHONY: deploy destroy status test build logs help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

build: guard-project-id ## Build and push container image to GCR
	gcloud builds submit --tag $(IMAGE_TAG) --project $(PROJECT_ID)

deploy: guard-project-id ## Deploy collector to Cloud Run (creates SA, grants IAM, builds, deploys)
	@scripts/deploy.sh

destroy: guard-project-id ## Remove Cloud Run service and associated resources
	@scripts/destroy.sh

status: guard-project-id ## Show service URL, status, and instance count
	@scripts/status.sh

test: guard-project-id ## Send test OTLP payload and verify metrics in Cloud Monitoring
	@scripts/test.sh

logs: guard-project-id ## Tail Cloud Run service logs
	gcloud run services logs tail $(SERVICE_NAME) --region $(REGION) --project $(PROJECT_ID)
