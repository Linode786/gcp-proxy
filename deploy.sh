#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAMES=("erwan1" "erwan2")

REPO_NAME="viper-panel-repo"
DEFAULT_REGION="us-central1"
BACKEND="gcpx.dev-zoom.buzz:700"

MEMORY="1Gi"
CPU="1"
CONCURRENCY="450"

MIN_INSTANCES="1"
MAX_INSTANCES="16"

TIMEOUT="3600"

CPU_TARGET="0.70"
CONCURRENCY_TARGET="0.40"


image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/erwan:latest"
}


enable_services() {
  echo
  echo "Enabling required Google Cloud services..."

  gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com
}


ensure_repo() {
  if gcloud artifacts repositories describe "$REPO_NAME" \
    --location="$REGION" >/dev/null 2>&1; then

    echo "Artifact Registry repository [$REPO_NAME] already exists."
    return 0
  fi

  echo
  echo "Creating Artifact Registry repository [$REPO_NAME]..."

  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images"

  echo
  echo "Waiting for Artifact Registry repository..."

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if gcloud artifacts repositories describe "$REPO_NAME" \
      --location="$REGION" >/dev/null 2>&1; then

      echo "Artifact Registry repository is ready."
      return 0
    fi

    sleep 3
  done

  echo "Repository [$REPO_NAME] was created but is not ready yet."
  echo "Run the deployment again in a few seconds."
  exit 1
}


build_image() {
  image_name

  echo
  echo "=========================================="
  echo "Building Docker image"
  echo "=========================================="
  echo "Image: $IMAGE"
  echo

  gcloud builds submit \
    --tag "$IMAGE"
}


deploy_service() {
  local service_name="$1"

  image_name

  echo
  echo "=========================================="
  echo "Deploying [$service_name]"
  echo "=========================================="
  echo

  # Deploy Cloud Run service
  #
  # Service-level scaling:
  #   Minimum = 1
  #   Maximum = 16
  #
  # Revision-level scaling:
  #   Minimum = 1
  #   Maximum = 16
  gcloud run deploy "$service_name" \
    --image "$IMAGE" \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --execution-environment gen2 \
    --memory "$MEMORY" \
    --cpu "$CPU" \
    --concurrency "$CONCURRENCY" \
    --min "$MIN_INSTANCES" \
    --max "$MAX_INSTANCES" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --timeout "$TIMEOUT" \
    --set-env-vars "BACKEND=$BACKEND"

  echo
  echo "Applying custom autoscaling targets to [$service_name]..."
  echo

  # Apply custom autoscaling targets
  gcloud beta run services update "$service_name" \
    --region "$REGION" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --scaling-cpu-target="$CPU_TARGET" \
    --scaling-concurrency-target="$CONCURRENCY_TARGET"

  echo
  echo "Deployment completed for [$service_name]."
  echo
  echo "Cloud Run URL:"

  gcloud run services describe "$service_name" \
    --region "$REGION" \
    --format="value(status.url)"

  echo
}


deploy_all_services() {
  for service_name in "${SERVICE_NAMES[@]}"; do
    deploy_service "$service_name"
  done
}


# ============================================================
# AUTO DEPLOY
# ============================================================

REGION="$DEFAULT_REGION"

echo
echo "=========================================="
echo "Cloud Run Automatic Deployment"
echo "=========================================="
echo
echo "Region:              $REGION"
echo "Services:            ${SERVICE_NAMES[*]}"
echo "Backend:             $BACKEND"
echo "Memory:              $MEMORY"
echo "CPU:                 $CPU"
echo "Concurrency:         $CONCURRENCY"
echo "Min Instances:       $MIN_INSTANCES"
echo "Max Instances:       $MAX_INSTANCES"
echo "CPU Target:          $CPU_TARGET"
echo "Concurrency Target:  $CONCURRENCY_TARGET"
echo "Timeout:             $TIMEOUT"
echo

enable_services
ensure_repo
build_image
deploy_all_services

echo
echo "=========================================="
echo "All deployments completed successfully."
echo "=========================================="
echo
