#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="erwan"
REPO_NAME="viper-panel-repo"
DEFAULT_REGION="us-central1"
BACKEND="gcpx.dev-zoom.buzz:700"

MEMORY="512Mi"
CPU="1"
CONCURRENCY="500"

MIN_INSTANCES="0"
MAX_INSTANCES="16"

TIMEOUT="3600"

CPU_TARGET="0.70"
CONCURRENCY_TARGET="0.40"

# Enable Cloud Run session affinity
SESSION_AFFINITY="true"


image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$SERVICE_NAME:latest"
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
  image_name

  echo
  echo "=========================================="
  echo "Deploying Cloud Run service [$SERVICE_NAME]"
  echo "=========================================="
  echo

  gcloud run deploy "$SERVICE_NAME" \
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
    --session-affinity \
    --set-env-vars "BACKEND=$BACKEND"

  echo
  echo "Applying custom autoscaling targets..."

  gcloud beta run services update "$SERVICE_NAME" \
    --region "$REGION" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --scaling-cpu-target="$CPU_TARGET" \
    --scaling-concurrency-target="$CONCURRENCY_TARGET" \
    --session-affinity

  echo
  echo "Verifying Cloud Run configuration..."
  echo

  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION"

  echo
  echo "=========================================="
  echo "Deployment completed successfully."
  echo "=========================================="
  echo
  echo "Cloud Run URL:"

  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(status.url)"

  echo
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
echo "Service:             $SERVICE_NAME"
echo "Region:              $REGION"
echo "Backend:             $BACKEND"
echo "Memory:              $MEMORY"
echo "CPU:                 $CPU"
echo "Concurrency:         $CONCURRENCY"
echo "Service Min:         $MIN_INSTANCES"
echo "Service Max:         $MAX_INSTANCES"
echo "Revision Min:        $MIN_INSTANCES"
echo "Revision Max:        $MAX_INSTANCES"
echo "CPU Target:          $CPU_TARGET"
echo "Concurrency Target:  $CONCURRENCY_TARGET"
echo "Session Affinity:    ENABLED"
echo "Timeout:             $TIMEOUT"
echo

enable_services
ensure_repo
build_image
deploy_service
