#!/bin/bash

# Create ECS service for first-time deployment
# Usage: ./scripts/create-service.sh

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

# Required environment variables
: ${AWS_REGION:="us-east-1"}
: ${ECS_CLUSTER_NAME:?"ECS_CLUSTER_NAME must be set"}
: ${ECS_SERVICE_NAME:?"ECS_SERVICE_NAME must be set"}

echo "🚀 Creating ECS service for first-time deployment..."
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Service: $ECS_SERVICE_NAME"
echo "Region: $AWS_REGION"

# Check if service already exists
if aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].serviceName' --output text 2>/dev/null | grep -q $ECS_SERVICE_NAME; then
    echo "❌ Service $ECS_SERVICE_NAME already exists in cluster $ECS_CLUSTER_NAME"
    echo "Use './scripts/deploy.sh' for updates to existing services"
    exit 1
fi

# Validate that aws/service.json exists and has been customized
if [ ! -f "aws/service.json" ]; then
    echo "❌ aws/service.json not found. Make sure you're in the project root directory."
    exit 1
fi

# Check if the file still contains template placeholders
if grep -q "CLUSTER_NAME\|subnet-XXXXXXXXX\|sg-XXXXXXXXX" aws/service.json; then
    echo "❌ aws/service.json still contains template placeholders."
    echo "Please update the following in aws/service.json:"
    echo "  - CLUSTER_NAME → $ECS_CLUSTER_NAME"
    echo "  - subnet-XXXXXXXXX → your actual subnet IDs"
    echo "  - sg-XXXXXXXXX → your actual security group ID"
    echo "  - Update target group ARN"
    exit 1
fi

# Create the service
echo "📝 Creating ECS service..."
aws ecs create-service --cli-input-json file://aws/service.json --region $AWS_REGION

echo "✅ ECS service created successfully!"
echo "You can now deploy updates using: ./scripts/deploy.sh"