#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-viper-panel}"
REPO_NAME="${REPO_NAME:-viper-panel-repo}"
DEFAULT_REGION="${REGION:-us-east1}"
BACKEND="${BACKEND:-gcpx.dev-zoom.buzz:700}"
MEMORY="${MEMORY:-2Gi}"
CPU="${CPU:-2}"
CONCURRENCY="${CONCURRENCY:-1000}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-8}"
TIMEOUT="${TIMEOUT:-3600}"

read_service_name() {
  read -r -p "Enter Cloud Run service name [$SERVICE_NAME]: " input_service_name
  SERVICE_NAME="${input_service_name:-$SERVICE_NAME}"
}

choose_region() {
  echo "Choose Cloud Run region:"
  echo "1) us-east1            United States, Qwiklabs friendly"
  echo "2) us-central1         United States"
  echo "3) europe-west1        Europe"
  echo "4) asia-southeast1     Singapore"
  echo "5) asia-southeast2     Jakarta"
  echo "6) me-central1         Doha"
  read -r -p "Enter 1, 2, 3, 4, 5, or 6 [$DEFAULT_REGION]: " choice

  case "$choice" in
    1) REGION="us-east1" ;;
    2) REGION="us-central1" ;;
    3) REGION="europe-west1" ;;
    4) REGION="asia-southeast1" ;;
    5) REGION="asia-southeast2" ;;
    6) REGION="me-central1" ;;
    *) REGION="$DEFAULT_REGION" ;;
  esac
}

read_backend_config() {
  read -r -p "Enter backend server [$BACKEND]: " input_backend
  BACKEND="${input_backend:-$BACKEND}"
}

read_runtime_settings() {
  echo "Runtime settings:"

  read -r -p "Memory [$MEMORY]: " input_memory
  MEMORY="${input_memory:-$MEMORY}"

  read -r -p "CPU [$CPU]: " input_cpu
  CPU="${input_cpu:-$CPU}"

  read -r -p "Concurrency [$CONCURRENCY]: " input_concurrency
  CONCURRENCY="${input_concurrency:-$CONCURRENCY}"

  read -r -p "Min instances [$MIN_INSTANCES]: " input_min_instances
  MIN_INSTANCES="${input_min_instances:-$MIN_INSTANCES}"

  read -r -p "Max instances [$MAX_INSTANCES]: " input_max_instances
  MAX_INSTANCES="${input_max_instances:-$MAX_INSTANCES}"

  read -r -p "Timeout seconds [$TIMEOUT]: " input_timeout
  TIMEOUT="${input_timeout:-$TIMEOUT}"
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
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images" 2>/dev/null || true
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

test_service() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    echo "Choose option 1 first to install/redeploy the service."
    return 0
  fi

  url="$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format="value(status.url)")"
  echo "Testing $url"
  echo

  code="$(curl --http1.1 -k -s -o /dev/null -w "%{http_code}" "$url")"
  echo "OVPN HTTP check -> $code"

  code="$(curl --http1.1 -k -s -o /dev/null -w "%{http_code}" \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
    "$url")"
  echo "OVPN WebSocket check -> $code"
}

show_logs() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    echo "Choose option 1 first to install/redeploy the service."
    return 0
  fi

  gcloud run services logs read "$SERVICE_NAME" \
    --region "$REGION" \
    --limit 50
}

delete_all() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]. Nothing to delete."
  else
    gcloud run services delete "$SERVICE_NAME" \
      --region "$REGION" \
      --quiet
  fi

  gcloud artifacts repositories delete "$REPO_NAME" \
    --location="$REGION" \
    --quiet 2>/dev/null || true
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
      read_service_name
      choose_region
      read_backend_config
      read_runtime_settings
      enable_services
      ensure_repo
      build_image
      deploy_service
      ;;
    2)
      read_service_name
      choose_region
      read_backend_config
      update_config_only
      ;;
    3)
      read_service_name
      choose_region
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
