#!/bin/bash

# Deployment script for WorthIt YouTube Transcript Service
# Usage: ./deploy.sh

set -e  # Exit on any error

echo "🚀 Starting deployment to Google Cloud Run..."

# Get project ID
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: No Google Cloud project set. Run 'gcloud config set project YOUR_PROJECT_ID'"
    exit 1
fi

echo "📋 Project ID: $PROJECT_ID"

# Get current git commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "📝 Commit: $COMMIT_HASH"

# Build and deploy
echo "🏗️  Building and deploying..."
gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions=_IMAGE=europe-west1-docker.pkg.dev/$PROJECT_ID/worthit-repo/worthit:$COMMIT_HASH \
  .

echo "✅ Deployment completed successfully!"
echo "🌐 Service URL: https://worthit-1023767329330.europe-west1.run.app"

