#!/bin/bash

# Deploy application to AWS ECS
# Usage: ./scripts/deploy.sh

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

# Required environment variables
: ${AWS_REGION:="us-east-1"}
: ${ECS_CLUSTER_NAME:?"ECS_CLUSTER_NAME must be set"}
: ${ECS_SERVICE_NAME:?"ECS_SERVICE_NAME must be set"}
: ${ECR_REPOSITORY_URI:?"ECR_REPOSITORY_URI must be set"}
: ${AWS_ACCOUNT_ID:?"AWS_ACCOUNT_ID must be set"}

echo "🚀 Deploying to AWS ECS..."
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Service: $ECS_SERVICE_NAME"
echo "Region: $AWS_REGION"

# Step 1: Build and push image
echo "📦 Building and pushing Docker image..."
./scripts/build-and-push.sh

# Step 2: Check if service exists and handle accordingly
echo "🔍 Checking if ECS service exists..."

# Check if service exists
if aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].serviceName' --output text 2>/dev/null | grep -q $ECS_SERVICE_NAME; then
    echo "✅ Service exists, updating with new image..."
    
    # Use the local template task definition and update with current image
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
    NEW_IMAGE_URI="$ECR_REPOSITORY_URI:$GIT_COMMIT"
    
    # Create new task definition with updated image using local template
    cat aws/task-definition.json | \
        jq --arg IMAGE "$NEW_IMAGE_URI" '.containerDefinitions[0].image = $IMAGE' \
        > /tmp/new-task-def.json
    
    # Register new task definition
    echo "🔄 Registering new task definition..."
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/new-task-def.json \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    echo "New task definition: $NEW_TASK_DEF_ARN"
else
    echo "📝 Service doesn't exist, creating for first deployment..."
    
    # Use the template task definition and update with current image
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
    NEW_IMAGE_URI="$ECR_REPOSITORY_URI:$GIT_COMMIT"
    
    # Update task definition template with current image
    cat aws/task-definition.json | \
        jq --arg IMAGE "$NEW_IMAGE_URI" '.containerDefinitions[0].image = $IMAGE' \
        > /tmp/new-task-def.json
    
    # Register new task definition
    echo "🔄 Registering task definition..."
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/new-task-def.json \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    echo "New task definition: $NEW_TASK_DEF_ARN"
    
    # Create the service using the service template
    echo "🚀 Creating ECS service..."
    aws ecs create-service --cli-input-json file://aws/service.json --region $AWS_REGION
    echo "✅ ECS service created successfully!"
fi

# Step 3: Update service with new task definition (if service already existed)
if aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE\|RUNNING"; then
    echo "🔄 Updating existing ECS service..."
    aws ecs update-service \
        --cluster $ECS_CLUSTER_NAME \
        --service $ECS_SERVICE_NAME \
        --task-definition $NEW_TASK_DEF_ARN \
        --force-new-deployment \
        --region $AWS_REGION \
        --output text > /dev/null
    echo "✅ Service update initiated"
else
    echo "✅ Service was just created, no update needed."
fi

# Step 4: Monitor deployment progress
echo "⏳ Monitoring deployment progress..."

# Wait a moment for the new task to start
sleep 10

# Get the latest task that was started
echo "🔍 Finding new task..."
LATEST_TASK=$(aws ecs list-tasks \
    --cluster $ECS_CLUSTER_NAME \
    --service-name $ECS_SERVICE_NAME \
    --region $AWS_REGION \
    --query 'taskArns[0]' \
    --output text)

if [ "$LATEST_TASK" != "None" ] && [ "$LATEST_TASK" != "" ]; then
    TASK_ID=$(basename $LATEST_TASK)
    echo "📋 Latest task: $TASK_ID"
    
    # Stream logs from the new task
    echo "📜 Streaming logs from new task..."
    LOG_STREAM="ecs/api-container/$TASK_ID"
    NEXT_TOKEN=""
    
    # Try to get logs for up to 2 minutes
    for i in {1..24}; do
        echo "--- Log check attempt $i ---"
        
        # Get new log events only
        if [ -n "$NEXT_TOKEN" ]; then
            LOG_RESULT=$(aws logs get-log-events \
                --log-group-name "/ecs/my-aws-template" \
                --log-stream-name "$LOG_STREAM" \
                --region $AWS_REGION \
                --next-token "$NEXT_TOKEN" \
                --output json 2>/dev/null)
        else
            LOG_RESULT=$(aws logs get-log-events \
                --log-group-name "/ecs/my-aws-template" \
                --log-stream-name "$LOG_STREAM" \
                --region $AWS_REGION \
                --output json 2>/dev/null)
        fi
        
        if [ $? -eq 0 ] && [ -n "$LOG_RESULT" ]; then
            # Extract and display new messages
            echo "$LOG_RESULT" | jq -r '.events[].message' 2>/dev/null || echo "Waiting for logs..."
            # Update next token for subsequent calls
            NEXT_TOKEN=$(echo "$LOG_RESULT" | jq -r '.nextForwardToken // empty' 2>/dev/null)
        else
            echo "Waiting for logs..."
        fi
        
        sleep 5
        
        # Check if task is running
        TASK_STATUS=$(aws ecs describe-tasks \
            --cluster $ECS_CLUSTER_NAME \
            --tasks $LATEST_TASK \
            --region $AWS_REGION \
            --query 'tasks[0].lastStatus' \
            --output text 2>/dev/null)
        
        if [ "$TASK_STATUS" = "RUNNING" ]; then
            echo "✅ Task is now running!"
            break
        elif [ "$TASK_STATUS" = "STOPPED" ]; then
            echo "❌ Task stopped - checking exit reason..."
            aws ecs describe-tasks \
                --cluster $ECS_CLUSTER_NAME \
                --tasks $LATEST_TASK \
                --region $AWS_REGION \
                --query 'tasks[0].stoppedReason' \
                --output text
            break
        fi
    done
else
    echo "⚠️  Could not find new task - checking service status..."
fi

# Step 5: Check deployment status
echo "✅ Deployment completed successfully!"

# Get service details
echo "📊 Service Status:"
aws ecs describe-services \
    --cluster $ECS_CLUSTER_NAME \
    --services $ECS_SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].{ServiceName:serviceName,Status:status,RunningCount:runningCount,DesiredCount:desiredCount,TaskDefinition:taskDefinition}'

echo "🎉 Deployment finished!"

# Clean up temporary files
rm -f /tmp/current-task-def.json /tmp/new-task-def.json