#!/bin/bash

# Build and push Docker image to ECR
# Usage: ./scripts/build-and-push.sh

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

# Required environment variables
: ${AWS_REGION:="us-east-1"}
: ${ECR_REPOSITORY_URI:?"ECR_REPOSITORY_URI must be set"}
: ${AWS_ACCOUNT_ID:?"AWS_ACCOUNT_ID must be set"}

# Extract repository name from URI
REPO_NAME=$(echo $ECR_REPOSITORY_URI | cut -d'/' -f2)

echo "🔧 Building and pushing Docker image..."
echo "Repository: $REPO_NAME"
echo "Region: $AWS_REGION"

# Get the login token and login to ECR
echo "🔐 Logging into Amazon ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the docker image for linux/amd64 platform (required for ECS Fargate)
echo "🐳 Building Docker image for linux/amd64..."
docker build --platform linux/amd64 -t $REPO_NAME .

# Tag the image
echo "🏷️  Tagging image..."
docker tag $REPO_NAME:latest $ECR_REPOSITORY_URI:latest

# Get git commit hash for additional tag
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
docker tag $REPO_NAME:latest $ECR_REPOSITORY_URI:$GIT_COMMIT

# Push the image to ECR
echo "🚀 Pushing image to ECR..."
docker push $ECR_REPOSITORY_URI:latest
docker push $ECR_REPOSITORY_URI:$GIT_COMMIT

echo "✅ Successfully pushed image to ECR!"
echo "Image URI: $ECR_REPOSITORY_URI:latest"
echo "Image URI: $ECR_REPOSITORY_URI:$GIT_COMMIT"