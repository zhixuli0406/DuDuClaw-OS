#!/usr/bin/env bash
# Build the public site (website/ + docs) and deploy it to Cloud Run.
#
#   scripts/deploy-cloudrun.sh            # build + deploy
#   SKIP_BUILD=1 scripts/deploy-cloudrun.sh   # reuse an existing _site/
#
# Project/region/account follow the DuDu Studio GCP convention: project
# louis-460302, region asia-east1, deploys run as the deployer service
# account (never an interactive login). Domain mapping is a one-time step
# documented in website/README.md, not part of this script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="${SERVICE:-duduclaw-os-site}"
PROJECT="${PROJECT:-louis-460302}"
REGION="${REGION:-asia-east1}"
ACCOUNT="${ACCOUNT:-xuanhe-deployer@louis-460302.iam.gserviceaccount.com}"
SITE_URL="${SITE_URL:-https://os.duduclaw.dudustudio.monster}"
export SITE_URL DOCS_BASE="${DOCS_BASE:-/docs}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build-site.sh"
fi
[[ -f "$ROOT/_site/index.html" ]] || { echo "_site/index.html missing; run scripts/build-site.sh" >&2; exit 1; }

STAGE="$ROOT/deploy/cloudrun/_site"
rm -rf "$STAGE"
cp -R "$ROOT/_site" "$STAGE"
echo "staged $(find "$STAGE" -type f | wc -l | tr -d ' ') files"

gcloud --account="$ACCOUNT" --project="$PROJECT" run deploy "$SERVICE" \
  --source "$ROOT/deploy/cloudrun" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port 80 \
  --cpu 1 --memory 256Mi \
  --min-instances 0 --max-instances 3 \
  --quiet

gcloud --account="$ACCOUNT" --project="$PROJECT" run services describe "$SERVICE" \
  --region "$REGION" --format="value(status.url)"
