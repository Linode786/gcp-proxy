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


read_backend_config() {
  read -r -p "Enter backend server [$BACKEND]: " input_backend
  BACKEND="${input_backend:-$BACKEND}"
}


image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/erwan:latest"
}


service_exists() {
  local service_name="$1"

  gcloud run services describe "$service_name" \
    --region "$REGION" \
    --format="value(metadata.name)" >/dev/null 2>&1
}


enable_services() {
  gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com
}


ensure_repo() {
  if gcloud artifacts repositories describe "$REPO_NAME" \
    --location="$REGION" >/dev/null 2>&1; then
    return 0
  fi

  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images"

  echo "Waiting for Artifact Registry repository..."

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if gcloud artifacts repositories describe "$REPO_NAME" \
      --location="$REGION" >/dev/null 2>&1; then
      return 0
    fi

    sleep 3
  done

  echo "Repository [$REPO_NAME] was created but is not ready yet."
  echo "Run deploy again in a few seconds."
  exit 1
}


build_image() {
  image_name

  gcloud builds submit \
    --tag "$IMAGE"
}


deploy_service() {
  local service_name="$1"

  image_name

  echo
  echo "Deploying Cloud Run service [$service_name]..."

  # Deploy the Cloud Run service
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
    --timeout "$TIMEOUT" \
    --set-env-vars "BACKEND=$BACKEND"

  # Apply custom autoscaling targets
  gcloud beta run services update "$service_name" \
    --region "$REGION" \
    --scaling-cpu-target="$CPU_TARGET" \
    --scaling-concurrency-target="$CONCURRENCY_TARGET"

  echo
  echo "Done. Cloud Run URL for [$service_name]:"

  gcloud run services describe "$service_name" \
    --region "$REGION" \
    --format="value(status.url)"
}


deploy_all_services() {
  for service_name in "${SERVICE_NAMES[@]}"; do
    deploy_service "$service_name"
  done
}


update_config_only() {
  for service_name in "${SERVICE_NAMES[@]}"; do

    echo
    echo "Updating [$service_name]..."

    if ! service_exists "$service_name"; then
      echo "Service [$service_name] was not found in region [$REGION]."

      read -r -p "Install/redeploy [$service_name] now? [y/N]: " install_now

      case "$install_now" in
        y|Y|yes|YES)
          deploy_service "$service_name"
          ;;

        *)
          echo "Skipping [$service_name]."
          ;;
      esac

      continue
    fi

    gcloud run services update "$service_name" \
      --region "$REGION" \
      --set-env-vars "BACKEND=$BACKEND"

    echo "Backend updated for [$service_name]."
  done
}


delete_all() {
  for service_name in "${SERVICE_NAMES[@]}"; do

    if ! service_exists "$service_name"; then
      echo "Service [$service_name] was not found in region [$REGION]. Nothing to delete."
    else
      echo "Deleting Cloud Run service [$service_name]..."

      gcloud run services delete "$service_name" \
        --region "$REGION" \
        --quiet
    fi

  done

  if gcloud artifacts repositories describe "$REPO_NAME" \
    --location="$REGION" >/dev/null 2>&1; then

    echo "Deleting Artifact Registry repository [$REPO_NAME]..."

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
      deploy_all_services
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
