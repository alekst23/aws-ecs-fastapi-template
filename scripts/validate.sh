#!/bin/bash

# Validate AWS infrastructure and configuration
# Usage: ./scripts/validate.sh

set -e

echo "🔍 Validating AWS ECS Template Configuration"
echo "============================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Run ./scripts/setup.sh first."
    exit 1
fi

# Load environment variables
export $(cat .env | grep -v '#' | awk '/=/ {print $1}')

# Required environment variables
MISSING_VARS=""

check_var() {
    local var_name=$1
    local var_value=${!var_name}
    if [ -z "$var_value" ]; then
        MISSING_VARS="$MISSING_VARS $var_name"
        echo "❌ $var_name is not set"
    else
        echo "✅ $var_name: $var_value"
    fi
}

echo "📋 Checking environment variables..."
check_var "AWS_REGION"
check_var "AWS_ACCOUNT_ID" 
check_var "ECR_REPOSITORY_URI"
check_var "ECS_CLUSTER_NAME"
check_var "ECS_SERVICE_NAME"
check_var "APP_NAME"

if [ ! -z "$MISSING_VARS" ]; then
    echo
    echo "❌ Missing required environment variables:$MISSING_VARS"
    echo "Run ./scripts/setup.sh to configure them."
    exit 1
fi

echo
echo "🔍 Validating AWS resources..."

# Check AWS CLI access
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured or invalid"
    exit 1
fi

CURRENT_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
if [ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
    echo "❌ AWS account mismatch. Expected: $AWS_ACCOUNT_ID, Current: $CURRENT_ACCOUNT"
    exit 1
fi
echo "✅ AWS credentials valid for account: $AWS_ACCOUNT_ID"

# Check ECR repository
if aws ecr describe-repositories --repository-names $(basename $ECR_REPOSITORY_URI) --region $AWS_REGION &> /dev/null; then
    echo "✅ ECR repository exists: $(basename $ECR_REPOSITORY_URI)"
else
    echo "❌ ECR repository not found: $(basename $ECR_REPOSITORY_URI)"
    exit 1
fi

# Check ECS cluster
if aws ecs describe-clusters --clusters $ECS_CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "✅ ECS cluster exists and active: $ECS_CLUSTER_NAME"
else
    echo "❌ ECS cluster not found or not active: $ECS_CLUSTER_NAME"
    exit 1
fi

# Check IAM roles
if aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
    echo "✅ ecsTaskExecutionRole exists"
else
    echo "❌ ecsTaskExecutionRole not found"
    exit 1
fi

if aws iam get-role --role-name ecsTaskRole &> /dev/null; then
    echo "✅ ecsTaskRole exists"
else
    echo "❌ ecsTaskRole not found"
    exit 1
fi

# Check security group
SG_NAME="${APP_NAME}-ecs-sg"
if aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -q "sg-"; then
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text)
    echo "✅ Security group exists: $SG_ID"
else
    echo "❌ Security group not found: $SG_NAME"
    exit 1
fi

# Check target group
TG_NAME="${APP_NAME}-tg"
if aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION &> /dev/null; then
    TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
    echo "✅ Target group exists: $TG_ARN"
else
    echo "❌ Target group not found: $TG_NAME"
    exit 1
fi

# Check load balancer
ALB_NAME="${APP_NAME}-alb"
if aws elbv2 describe-load-balancers --names $ALB_NAME --region $AWS_REGION &> /dev/null; then
    ALB_DNS=$(aws elbv2 describe-load-balancers --names $ALB_NAME --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)
    echo "✅ Load balancer exists: $ALB_DNS"
else
    echo "❌ Load balancer not found: $ALB_NAME"
    exit 1
fi

# Check CloudWatch log group
LOG_GROUP="/ecs/$APP_NAME"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region $AWS_REGION --query 'logGroups[?logGroupName==`'$LOG_GROUP'`]' --output text | grep -q "$LOG_GROUP"; then
    echo "✅ CloudWatch log group exists: $LOG_GROUP"
else
    echo "❌ CloudWatch log group not found: $LOG_GROUP"
    exit 1
fi

echo
echo "📄 Checking configuration files..."

# Check task definition file
if [ -f "aws/task-definition.json" ]; then
    if grep -q "ACCOUNT_ID\|REGION" aws/task-definition.json; then
        echo "❌ aws/task-definition.json still contains template placeholders"
        exit 1
    else
        echo "✅ aws/task-definition.json is configured"
    fi
else
    echo "❌ aws/task-definition.json not found"
    exit 1
fi

# Check service definition file
if [ -f "aws/service.json" ]; then
    if grep -q "CLUSTER_NAME\|subnet-XXXXXXXXX\|sg-XXXXXXXXX" aws/service.json; then
        echo "❌ aws/service.json still contains template placeholders"
        exit 1
    else
        echo "✅ aws/service.json is configured"
    fi
else
    echo "❌ aws/service.json not found"
    exit 1
fi

echo
echo "🚀 Checking deployment status..."

# Check ECS service status
if aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION &> /dev/null; then
    SERVICE_STATUS=$(aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].status' --output text)
    RUNNING_COUNT=$(aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].runningCount' --output text)
    DESIRED_COUNT=$(aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].desiredCount' --output text)
    
    echo "✅ ECS service exists: $ECS_SERVICE_NAME"
    echo "   Status: $SERVICE_STATUS"
    echo "   Running tasks: $RUNNING_COUNT/$DESIRED_COUNT"
    
    if [ "$RUNNING_COUNT" = "0" ]; then
        echo "❌ No tasks are currently running!"
        
        # Check latest task for errors
        LATEST_TASK=$(aws ecs list-tasks --cluster $ECS_CLUSTER_NAME --service-name $ECS_SERVICE_NAME --region $AWS_REGION --query 'taskArns[0]' --output text 2>/dev/null)
        if [ "$LATEST_TASK" != "None" ] && [ "$LATEST_TASK" != "" ]; then
            echo "   Checking latest task: $(basename $LATEST_TASK)"
            TASK_STATUS=$(aws ecs describe-tasks --cluster $ECS_CLUSTER_NAME --tasks $LATEST_TASK --region $AWS_REGION --query 'tasks[0].lastStatus' --output text 2>/dev/null)
            echo "   Latest task status: $TASK_STATUS"
            
            if [ "$TASK_STATUS" = "STOPPED" ]; then
                STOP_REASON=$(aws ecs describe-tasks --cluster $ECS_CLUSTER_NAME --tasks $LATEST_TASK --region $AWS_REGION --query 'tasks[0].stoppedReason' --output text 2>/dev/null)
                echo "   Stop reason: $STOP_REASON"
                
                # Show recent logs
                TASK_ID=$(basename $LATEST_TASK)
                LOG_STREAM="ecs/api-container/$TASK_ID"
                echo "   Recent logs:"
                aws logs get-log-events \
                    --log-group-name "/ecs/my-aws-template" \
                    --log-stream-name "$LOG_STREAM" \
                    --region $AWS_REGION \
                    --query 'events[-5:].message' \
                    --output text 2>/dev/null | sed 's/^/     /' || echo "     No logs available"
            fi
        fi
    else
        echo "✅ Tasks are running successfully"
    fi
else
    echo "❌ ECS service not found: $ECS_SERVICE_NAME"
    echo "   Run ./scripts/deploy.sh to create the service"
fi

# Check target group health
echo
echo "🏥 Checking target group health..."
TG_HEALTH=$(aws elbv2 describe-target-health --target-group-arn $TG_ARN --region $AWS_REGION --query 'TargetHealthDescriptions[].TargetHealth.State' --output text 2>/dev/null)
if [ -n "$TG_HEALTH" ]; then
    echo "Target health states: $TG_HEALTH"
    if echo "$TG_HEALTH" | grep -q "healthy"; then
        echo "✅ At least one target is healthy"
    else
        echo "❌ No healthy targets found"
        echo "   Possible issues:"
        echo "   - Container not listening on port 8000"
        echo "   - Health check failing at /health endpoint"
        echo "   - Security group blocking traffic"
    fi
else
    echo "❌ No targets registered in target group"
fi

# Test health endpoint
echo
echo "🌐 Testing API endpoint..."
if curl -f -s --max-time 10 "http://$ALB_DNS/health" > /tmp/health_check 2>&1; then
    HEALTH_RESPONSE=$(cat /tmp/health_check)
    echo "✅ API health check successful: $HEALTH_RESPONSE"
    echo "🌐 Your API is available at: http://$ALB_DNS"
    echo "📖 API docs available at: http://$ALB_DNS/docs"
else
    echo "❌ API health check failed"
    echo "   Error: $(cat /tmp/health_check 2>/dev/null || echo 'Connection timeout or refused')"
    echo "   Troubleshooting steps:"
    echo "   1. Check if ECS tasks are running (see above)"
    echo "   2. Verify target group health (see above)"
    echo "   3. Check security group allows traffic on port 8000"
    echo "   4. Verify load balancer listener is configured correctly"
fi

rm -f /tmp/health_check

echo
echo "🎉 Validation completed!"