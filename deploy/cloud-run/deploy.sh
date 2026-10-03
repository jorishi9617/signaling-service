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

NEON_DATABASE_URL="$(neon connection-string production --database-name neondb)"
if [[ "$NEON_DATABASE_URL" != postgresql://* && "$NEON_DATABASE_URL" != postgres://* ]]; then
  echo "Could not retrieve the linked Neon production connection string." >&2
  echo "Check that the Neon CLI is authenticated and this repo is linked to the right project." >&2
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
printf '%s' "$NEON_DATABASE_URL" | python3 -c '
import sys
import urllib.parse

url = urllib.parse.urlsplit(sys.stdin.read())
if url.scheme not in ("postgres", "postgresql") or not url.hostname or not url.path:
    raise SystemExit("Neon returned an invalid PostgreSQL connection URL")
if "-pooler." in url.hostname:
    raise SystemExit("Use a direct Neon connection for startup Flyway migrations")
query = urllib.parse.parse_qsl(url.query, keep_blank_values=True)
if not any(key == "sslmode" for key, _ in query):
    query.append(("sslmode", "require"))
jdbc_url = urllib.parse.urlunsplit(("jdbc:postgresql", url.netloc, url.path, urllib.parse.urlencode(query), ""))
sys.stdout.write(jdbc_url)
' | gcloud secrets create video-db-url \
  --data-file=- --project="$PROJECT_ID"
unset NEON_DATABASE_URL

for secret in video-jwt-secret video-token-api-key video-db-url; do
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
  --set-secrets="DATABASE_URL=video-db-url:latest,JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="${COMMON_ENV}" \
  --project="$PROJECT_ID"

gcloud run deploy video-platform-call \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/call-service:latest" \
  --region="$REGION" --port=8080 --memory=512Mi --cpu=1 \
  --min=0 --max=1 --timeout=3600 --allow-unauthenticated \
  --service-account="$RUNTIME_SA" \
  --set-secrets="DATABASE_URL=video-db-url:latest,SECURITY_JWT_SECRET=video-jwt-secret:latest" \
  --set-env-vars="${COMMON_ENV}" \
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
