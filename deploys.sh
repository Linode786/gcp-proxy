#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-viper-panel}"
REPO_NAME="${REPO_NAME:-viper-panel-repo}"
DEFAULT_REGION="${REGION:-us-central1}"
BACKEND="${BACKEND:-gcpx.dev-zoom.buzz:700}"
MEMORY="${MEMORY:-8Gi}"
CPU="${CPU:-4}"
CONCURRENCY="${CONCURRENCY:-1000}"
MIN_INSTANCES="${MIN_INSTANCES:-1}"
MAX_INSTANCES="${MAX_INSTANCES:-4}"
TIMEOUT="${TIMEOUT:-3600}"

read_backend_config() {
  read -r -p "Enter backend server [$BACKEND]: " input_backend
  BACKEND="${input_backend:-$BACKEND}"
}

image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$SERVICE_NAME:latest"
}

service_exists() {
  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(metadata.name)" >/dev/null 2>&1
}

enable_services() {
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
}

ensure_repo() {
  if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1; then
    return 0
  fi

  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images"

  echo "Waiting for Artifact Registry repository..."
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done

  echo "Repository [$REPO_NAME] was created but is not ready yet. Run deploy again in a few seconds."
  exit 1
}

build_image() {
  image_name
  gcloud builds submit --tag "$IMAGE"
}

deploy_service() {
  image_name
  gcloud run deploy "$SERVICE_NAME" \
    --image "$IMAGE" \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --execution-environment gen2 \
    --memory "$MEMORY" \
    --cpu "$CPU" \
    --concurrency "$CONCURRENCY" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --timeout "$TIMEOUT" \
    --set-env-vars "BACKEND=$BACKEND"

  echo
  echo "Done. Your Cloud Run URL:"
  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(status.url)"
}

update_config_only() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    read -r -p "Install/redeploy it now? [y/N]: " install_now
    case "$install_now" in
      y|Y|yes|YES)
        enable_services
        ensure_repo
        build_image
        deploy_service
        ;;
      *)
        echo "Choose option 1 later to install/redeploy the service."
        ;;
    esac
    return 0
  fi

  gcloud run services update "$SERVICE_NAME" \
    --region "$REGION" \
    --set-env-vars "BACKEND=$BACKEND"
}

delete_all() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]. Nothing to delete."
  else
    gcloud run services delete "$SERVICE_NAME" \
      --region "$REGION" \
      --quiet
  fi

  if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1; then
    gcloud artifacts repositories delete "$REPO_NAME" \
      --location="$REGION" \
      --quiet
  else
    echo "Repository [$REPO_NAME] was not found in region [$REGION]. Nothing to delete."
  fi
}

while true; do
  echo
  echo "Cloud Run Proxy Menu"
  echo "1) Deploy"
  echo "2) Change Host"
  echo "3) Delete all"
  echo "4) Exit"
  read -r -p "Choose: " action
  echo

  case "$action" in
    1)
      REGION="$DEFAULT_REGION"
      enable_services
      ensure_repo
      build_image
      deploy_service
      ;;
    2)
      REGION="$DEFAULT_REGION"
      read_backend_config
      update_config_only
      ;;
    3)
      REGION="$DEFAULT_REGION"
      delete_all
      ;;
    4)
      exit 0
      ;;
    *)
      echo "Invalid choice."
      ;;
  esac
done
