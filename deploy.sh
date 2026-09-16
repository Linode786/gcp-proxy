```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# DEFAULT CONFIGURATION
# ============================================================

SERVICE_NAME="viper-panel"
REPO_NAME="viper-panel-repo"
REGION="us-central1"

BACKEND="gcpx.dev-zoom.buzz:700"

MEMORY="8Gi"
CPU="4"
CONCURRENCY="1000"

MIN_INSTANCES="1"
MAX_INSTANCES="4"

TIMEOUT="3600"


# ============================================================
# BACKEND CONFIGURATION
# ============================================================

read_backend_config() {
  read -r -p "Enter backend server [$BACKEND]: " input_backend
  BACKEND="${input_backend:-$BACKEND}"
}


# ============================================================
# IMAGE
# ============================================================

image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$SERVICE_NAME:latest"
}


# ============================================================
# CHECK SERVICE
# ============================================================

service_exists() {
  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(metadata.name)" >/dev/null 2>&1
}


# ============================================================
# ENABLE REQUIRED SERVICES
# ============================================================

enable_services() {
  gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com
}


# ============================================================
# ARTIFACT REGISTRY
# ============================================================

ensure_repo() {
  if gcloud artifacts repositories describe "$REPO_NAME" \
    --location="$REGION" >/dev/null 2>&1; then
    return 0
  fi

  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images"

  echo
  echo "Waiting for Artifact Registry repository..."

  for _ in {1..10}; do
    if gcloud artifacts repositories describe "$REPO_NAME" \
      --location="$REGION" >/dev/null 2>&1; then
      return 0
    fi

    sleep 3
  done

  echo
  echo "Repository [$REPO_NAME] was created but is not ready yet."
  echo "Run deploy again in a few seconds."
  exit 1
}


# ============================================================
# BUILD IMAGE
# ============================================================

build_image() {
  image_name

  echo
  echo "Building image:"
  echo "$IMAGE"
  echo

  gcloud builds submit --tag "$IMAGE"
}


# ============================================================
# DEPLOY CLOUD RUN
# ============================================================

deploy_service() {
  image_name

  echo
  echo "Deploying Cloud Run service..."
  echo
  echo "Service:       $SERVICE_NAME"
  echo "Region:        $REGION"
  echo "Memory:        $MEMORY"
  echo "CPU:           $CPU"
  echo "Concurrency:   $CONCURRENCY"
  echo "Min instances: $MIN_INSTANCES"
  echo "Max instances: $MAX_INSTANCES"
  echo "Timeout:       $TIMEOUT"
  echo "Backend:       $BACKEND"
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
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --timeout "$TIMEOUT" \
    --set-env-vars "BACKEND=$BACKEND"

  echo
  echo "============================================================"
  echo "Deployment complete."
  echo "============================================================"
  echo
  echo "Cloud Run URL:"

  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(status.url)"

  echo
  echo "Minimum instances:"

  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(spec.template.scaling.minInstanceCount)"

  echo
}


# ============================================================
# CHANGE BACKEND ONLY
# ============================================================

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

  echo "Updating backend to: $BACKEND"

  gcloud run services update "$SERVICE_NAME" \
    --region "$REGION" \
    --set-env-vars "BACKEND=$BACKEND"

  echo
  echo "Backend updated successfully."
}


# ============================================================
# DELETE EVERYTHING
# ============================================================

delete_all() {
  echo "Deleting Cloud Run service and Artifact Registry repository..."
  echo

  if service_exists; then
    gcloud run services delete "$SERVICE_NAME" \
      --region "$REGION" \
      --quiet

    echo "Cloud Run service deleted."
  else
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
  fi

  if gcloud artifacts repositories describe "$REPO_NAME" \
    --location="$REGION" >/dev/null 2>&1; then

    gcloud artifacts repositories delete "$REPO_NAME" \
      --location="$REGION" \
      --quiet

    echo "Artifact Registry repository deleted."
  else
    echo "Repository [$REPO_NAME] was not found in region [$REGION]."
  fi

  echo
  echo "Delete operation complete."
}


# ============================================================
# MENU
# ============================================================

while true; do

  echo
  echo "============================================================"
  echo "Cloud Run Proxy Menu"
  echo "============================================================"
  echo
  echo "Service:       $SERVICE_NAME"
  echo "Region:        $REGION"
  echo "Backend:       $BACKEND"
  echo "Memory:        $MEMORY"
  echo "CPU:           $CPU"
  echo "Concurrency:   $CONCURRENCY"
  echo "Min instances: $MIN_INSTANCES"
  echo "Max instances: $MAX_INSTANCES"
  echo "Timeout:       $TIMEOUT"
  echo
  echo "1) Deploy"
  echo "2) Change Host"
  echo "3) Delete all"
  echo "4) Exit"
  echo

  read -r -p "Choose: " action
  echo

  case "$action" in

    1)
      enable_services
      ensure_repo
      build_image
      deploy_service
      ;;

    2)
      read_backend_config
      update_config_only
      ;;

    3)
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
```
