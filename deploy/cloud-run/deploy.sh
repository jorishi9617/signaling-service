#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "Set your Google Cloud project first: gcloud config set project PROJECT_ID" >&2
  exit 1
fi

REGION=us-central1
REPOSITORY=video-platform
WORKDIR="${HOME}/video-platform-deploy"

read -r -p "Neon database host (no protocol): " DB_HOST
read -r -p "Neon database name: " DB_NAME
read -r -p "Neon database username: " DB_USER
read -r -s -p "Neon database password: " DB_PASSWORD
printf '\n'

if [[ -z "$DB_HOST" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
  echo "All Neon connection details are required." >&2
  exit 1
fi

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"

gcloud artifacts repositories create "$REPOSITORY" \
  --repository-format=docker \
  --location="$REGION" \
  --project="$PROJECT_ID"

gcloud iam service-accounts create video-platform-runtime \
  --display-name="Video platform Cloud Run services" \
  --project="$PROJECT_ID"

RUNTIME_SA="video-platform-runtime@${PROJECT_ID}.iam.gserviceaccount.com"

openssl rand -base64 48 -A | gcloud secrets create video-jwt-secret \
  --data-file=- --project="$PROJECT_ID"
openssl rand -hex 32 | tr -d '\n' | gcloud secrets create video-token-api-key \
  --data-file=- --project="$PROJECT_ID"
printf '%s' "$DB_PASSWORD" | gcloud secrets create video-db-password \
  --data-file=- --project="$PROJECT_ID"
unset DB_PASSWORD

for secret in video-jwt-secret video-token-api-key video-db-password; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role=roles/secretmanager.secretAccessor \
    --project="$PROJECT_ID"
done

mkdir -p "$WORKDIR"
for app in auth-service call-service common-library signaling-service; do
  git clone --depth 1 --branch master \
    "https://github.com/jorishi9617/${app}.git" "${WORKDIR}/${app}"
done

for app in auth-service call-service common-library signaling-service; do
  image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${app}:latest"
  gcloud builds submit "${WORKDIR}/${app}" \
    --tag="$image" \
    --project="$PROJECT_ID"
done

JAVA_OPTIONS="-XX:MaxRAMPercentage=50.0 -XX:+UseSerialGC"
DB_ENV="^~^DATABASE_URL=jdbc:postgresql://${DB_HOST}:5432/${DB_NAME}?sslmode=require~DATABASE_HOST=${DB_HOST}~DATABASE_PORT=5432~DATABASE_NAME=${DB_NAME}~DATABASE_USER=${DB_USER}~FRONTEND_ORIGINS=*~JAVA_TOOL_OPTIONS=${JAVA_OPTIONS}"
COMMON_ENV="^~^FRONTEND_ORIGINS=*~JAVA_TOOL_OPTIONS=${JAVA_OPTIONS}"

gcloud run deploy video-platform-token \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/common-library:latest" \
  --region="$REGION" --port=8080 --memory=512Mi --cpu=1 \
  --min=0 --max=1 --timeout=3600 --allow-unauthenticated \
  --service-account="$RUNTIME_SA" \
  --set-secrets="SECURITY_API_KEY=video-token-api-key:latest,SECURITY_JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="^~^JAVA_TOOL_OPTIONS=${JAVA_OPTIONS}" \
  --project="$PROJECT_ID"

gcloud run deploy video-platform-auth \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/auth-service:latest" \
  --region="$REGION" --port=8080 --memory=512Mi --cpu=1 \
  --min=0 --max=1 --timeout=3600 --allow-unauthenticated \
  --service-account="$RUNTIME_SA" \
  --set-secrets="DATABASE_PASSWORD=video-db-password:latest,JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="${DB_ENV}" \
  --project="$PROJECT_ID"

gcloud run deploy video-platform-call \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/call-service:latest" \
  --region="$REGION" --port=8080 --memory=512Mi --cpu=1 \
  --min=0 --max=1 --timeout=3600 --allow-unauthenticated \
  --service-account="$RUNTIME_SA" \
  --set-secrets="DATABASE_PASSWORD=video-db-password:latest,SECURITY_JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="^~^DATABASE_URL=jdbc:postgresql://${DB_HOST}:5432/${DB_NAME}?sslmode=require~DATABASE_USER=${DB_USER}~FRONTEND_ORIGINS=*~JAVA_TOOL_OPTIONS=${JAVA_OPTIONS}" \
  --project="$PROJECT_ID"

gcloud run deploy video-platform-signaling \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/signaling-service:latest" \
  --region="$REGION" --port=8080 --memory=512Mi --cpu=1 \
  --min=0 --max=1 --timeout=3600 --allow-unauthenticated \
  --service-account="$RUNTIME_SA" \
  --set-secrets="JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="${COMMON_ENV}" \
  --project="$PROJECT_ID"

printf '\nCloud Run service URLs:\n'
for service in token auth call signaling; do
  printf 'video-platform-%s: ' "$service"
  gcloud run services describe "video-platform-${service}" \
    --region="$REGION" --project="$PROJECT_ID" \
    --format="value(status.url)"
done
