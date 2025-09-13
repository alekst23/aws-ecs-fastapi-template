#!/bin/bash

# Check logs of the latest ECS task
# Usage: ./scripts/check-logs.sh

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | awk '/=/ {print $1}')
fi

# Required environment variables
: ${AWS_REGION:="us-east-1"}
: ${ECS_CLUSTER_NAME:?"ECS_CLUSTER_NAME must be set"}
: ${ECS_SERVICE_NAME:?"ECS_SERVICE_NAME must be set"}

echo "🔍 Finding latest task..."

# Get the latest task from service
LATEST_TASK=$(aws ecs list-tasks \
    --cluster $ECS_CLUSTER_NAME \
    --service-name $ECS_SERVICE_NAME \
    --region $AWS_REGION \
    --query 'taskArns[0]' \
    --output text 2>/dev/null)

if [ "$LATEST_TASK" = "None" ] || [ "$LATEST_TASK" = "" ]; then
    echo "⚠️  No active tasks found for service, checking all tasks in cluster..."
    
    # Get all tasks in the cluster (including stopped ones)
    LATEST_TASK=$(aws ecs list-tasks \
        --cluster $ECS_CLUSTER_NAME \
        --region $AWS_REGION \
        --desired-status STOPPED \
        --query 'taskArns[0]' \
        --output text 2>/dev/null)
    
    if [ "$LATEST_TASK" = "None" ] || [ "$LATEST_TASK" = "" ]; then
        echo "❌ No tasks found in cluster $ECS_CLUSTER_NAME"
        exit 1
    fi
    echo "📋 Found task in cluster: $(basename $LATEST_TASK)"
fi

TASK_ID=$(basename $LATEST_TASK)
echo "📋 Latest task: $TASK_ID"

# Get task status
TASK_STATUS=$(aws ecs describe-tasks \
    --cluster $ECS_CLUSTER_NAME \
    --tasks $LATEST_TASK \
    --region $AWS_REGION \
    --query 'tasks[0].lastStatus' \
    --output text 2>/dev/null)

echo "📊 Task status: $TASK_STATUS"

if [ "$TASK_STATUS" = "STOPPED" ]; then
    STOP_REASON=$(aws ecs describe-tasks \
        --cluster $ECS_CLUSTER_NAME \
        --tasks $LATEST_TASK \
        --region $AWS_REGION \
        --query 'tasks[0].stoppedReason' \
        --output text 2>/dev/null)
    echo "❌ Stop reason: $STOP_REASON"
fi

# Show logs
LOG_STREAM="ecs/api-container/$TASK_ID"
echo
echo "📜 Recent logs from $LOG_STREAM:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

aws logs get-log-events \
    --log-group-name "/ecs/my-aws-template" \
    --log-stream-name "$LOG_STREAM" \
    --region $AWS_REGION \
    --query 'events[].message' \
    --output text 2>/dev/null || echo "No logs available yet"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "💡 To stream logs in real-time, run:"
echo "   aws logs tail /ecs/my-aws-template --follow --region $AWS_REGION"