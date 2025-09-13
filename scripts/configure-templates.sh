#!/bin/bash

# Configure template files with actual values from .env
# Usage: ./scripts/configure-templates.sh

set -e

# Load environment variables
if [ ! -f .env ]; then
    echo "❌ .env file not found. Run ./scripts/setup.sh first."
    exit 1
fi

export $(cat .env | grep -v '#' | awk '/=/ {print $1}')

# Required environment variables
: ${AWS_REGION:?"AWS_REGION must be set"}
: ${AWS_ACCOUNT_ID:?"AWS_ACCOUNT_ID must be set"}
: ${ECR_REPOSITORY_URI:?"ECR_REPOSITORY_URI must be set"}
: ${ECS_CLUSTER_NAME:?"ECS_CLUSTER_NAME must be set"}
: ${ECS_SERVICE_NAME:?"ECS_SERVICE_NAME must be set"}
: ${APP_NAME:?"APP_NAME must be set"}

echo "🔧 Configuring template files..."

# Get infrastructure details
echo "🔍 Getting infrastructure details..."

# Get VPC and subnet information
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --region $AWS_REGION --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'Subnets[].SubnetId' --output text)
SUBNET_ARRAY=($SUBNET_IDS)

# Get security group ID
SG_NAME="${APP_NAME}-ecs-sg"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text)

# Get target group ARN
TG_NAME="${APP_NAME}-tg"
TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "VPC ID: $VPC_ID"
echo "Subnets: ${SUBNET_ARRAY[0]}, ${SUBNET_ARRAY[1]}"
echo "Security Group: $SG_ID"
echo "Target Group: $TG_ARN"

# Configure task-definition.json
echo
echo "📝 Configuring aws/task-definition.json..."

# Create configured task definition
cat > aws/task-definition.json << EOF
{
  "family": "$APP_NAME",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskRole",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "api-container",
      "image": "$ECR_REPOSITORY_URI:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$APP_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "environment": [
        {
          "name": "APP_NAME",
          "value": "$APP_NAME"
        },
        {
          "name": "APP_VERSION",
          "value": "1.0.0"
        },
        {
          "name": "DEBUG",
          "value": "false"
        },
        {
          "name": "ENVIRONMENT",
          "value": "$ENVIRONMENT"
        },
        {
          "name": "API_KEY",
          "value": "$API_KEY"
        },
        {
          "name": "ENABLE_API_KEY_AUTH",
          "value": "$ENABLE_API_KEY_AUTH"
        },
        {
          "name": "ENABLE_API_KEY_DOCS",
          "value": "$ENABLE_API_KEY_DOCS"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:8000/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Configure service.json
echo "📝 Configuring aws/service.json..."

cat > aws/service.json << EOF
{
  "serviceName": "$ECS_SERVICE_NAME",
  "cluster": "$ECS_CLUSTER_NAME",
  "taskDefinition": "$APP_NAME",
  "desiredCount": 2,
  "launchType": "FARGATE",
  "platformVersion": "LATEST",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": [
        "${SUBNET_ARRAY[0]}",
        "${SUBNET_ARRAY[1]}"
      ],
      "securityGroups": [
        "$SG_ID"
      ],
      "assignPublicIp": "ENABLED"
    }
  },
  "loadBalancers": [
    {
      "targetGroupArn": "$TG_ARN",
      "containerName": "api-container",
      "containerPort": 8000
    }
  ],
  "tags": [
    {
      "key": "Environment",
      "value": "$ENVIRONMENT"
    },
    {
      "key": "Project",
      "value": "$APP_NAME"
    }
  ],
  "enableExecuteCommand": true,
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50,
    "deploymentCircuitBreaker": {
      "enable": true,
      "rollback": true
    }
  },
  "healthCheckGracePeriodSeconds": 300
}
EOF

# Create CloudWatch log group
echo
echo "📊 Creating CloudWatch log group..."
if aws logs describe-log-groups --log-group-name-prefix "/ecs/$APP_NAME" --region $AWS_REGION --query 'logGroups[?logGroupName==`/ecs/'$APP_NAME'`]' --output text | grep -q "/ecs/$APP_NAME"; then
    echo "✅ Log group /ecs/$APP_NAME already exists"
else
    aws logs create-log-group --log-group-name "/ecs/$APP_NAME" --region $AWS_REGION
    echo "✅ Created log group: /ecs/$APP_NAME"
fi

echo
echo "✅ Template configuration complete!"
echo "📄 Configured files:"
echo "  - aws/task-definition.json"
echo "  - aws/service.json"
echo "  - CloudWatch log group: /ecs/$APP_NAME"