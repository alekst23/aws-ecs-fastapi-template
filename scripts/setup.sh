#!/bin/bash

# Interactive setup script for AWS ECS API Template
# This script creates all AWS resources and configures the template

set -e

echo "🚀 AWS ECS API Template Setup"
echo "=============================="
echo

# Check prerequisites
echo "📋 Checking prerequisites..."
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install it first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install it first."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

echo "✅ Prerequisites check passed!"
echo

# Get user input
echo "📝 Please provide the following information:"
echo

read -p "Project name (e.g., my-api): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "❌ Project name is required"
    exit 1
fi

read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Environment (dev/staging/prod) [dev]: " ENVIRONMENT
ENVIRONMENT=${ENVIRONMENT:-dev}

# Generate resource names
CLUSTER_NAME="${PROJECT_NAME}-cluster"
SERVICE_NAME="${PROJECT_NAME}-service"
REPO_NAME="${PROJECT_NAME}"
ALB_NAME="${PROJECT_NAME}-alb"
TG_NAME="${PROJECT_NAME}-tg"
SG_NAME="${PROJECT_NAME}-ecs-sg"

echo
echo "📊 Configuration Summary:"
echo "Project: $PROJECT_NAME"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo
read -p "Continue with setup? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Get AWS Account ID
echo
echo "🔍 Getting AWS account information..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $AWS_ACCOUNT_ID"

# Create ECR repository
echo
echo "📦 Creating ECR repository..."
if aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION &> /dev/null; then
    echo "✅ ECR repository $REPO_NAME already exists"
else
    aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION > /dev/null
    echo "✅ Created ECR repository: $REPO_NAME"
fi

ECR_REPOSITORY_URI=$(aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
echo "Repository URI: $ECR_REPOSITORY_URI"

# Create ECS cluster
echo
echo "🏗️  Creating ECS cluster..."
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q $CLUSTER_NAME; then
    echo "✅ ECS cluster $CLUSTER_NAME already exists"
else
    aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION > /dev/null
    echo "✅ Created ECS cluster: $CLUSTER_NAME"
fi

# Get VPC information
echo
echo "🌐 Getting VPC information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --region $AWS_REGION --query 'Vpcs[0].VpcId' --output text)
echo "Using VPC: $VPC_ID"

SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'Subnets[].SubnetId' --output text)
SUBNET_ARRAY=($SUBNET_IDS)
echo "Available subnets: ${SUBNET_ARRAY[@]}"

# Create security group
echo
echo "🔒 Creating security group..."
if aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -q "sg-"; then
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text)
    echo "✅ Security group $SG_NAME already exists: $SG_ID"
else
    SG_ID=$(aws ec2 create-security-group --group-name $SG_NAME --description "Security group for $PROJECT_NAME ECS tasks" --vpc-id $VPC_ID --region $AWS_REGION --query 'GroupId' --output text)
    # Allow HTTP traffic on port 80 (load balancer listener)
    aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $AWS_REGION > /dev/null
    # Allow HTTP traffic on port 8000 (container port)
    aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region $AWS_REGION > /dev/null
    echo "✅ Created security group: $SG_ID"
fi

# Create load balancer
echo
echo "⚖️  Creating Application Load Balancer..."
if aws elbv2 describe-load-balancers --names $ALB_NAME --region $AWS_REGION &> /dev/null; then
    ALB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME --region $AWS_REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    echo "✅ Load balancer $ALB_NAME already exists"
else
    ALB_ARN=$(aws elbv2 create-load-balancer --name $ALB_NAME --subnets ${SUBNET_ARRAY[0]} ${SUBNET_ARRAY[1]} --security-groups $SG_ID --region $AWS_REGION --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    echo "✅ Created load balancer: $ALB_NAME"
fi

# Create target group
echo
echo "🎯 Creating target group..."
if aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION &> /dev/null; then
    TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
    echo "✅ Target group $TG_NAME already exists"
else
    TG_ARN=$(aws elbv2 create-target-group --name $TG_NAME --protocol HTTP --port 8000 --vpc-id $VPC_ID --target-type ip --health-check-path /health --region $AWS_REGION --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener
    aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN --region $AWS_REGION > /dev/null
    echo "✅ Created target group and listener: $TG_NAME"
fi

# Create IAM roles if they don't exist
echo
echo "🔐 Creating IAM roles..."

# Task execution role
if aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
    echo "✅ ecsTaskExecutionRole already exists"
else
    aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {"Service": "ecs-tasks.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }
      ]
    }' > /dev/null
    aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    echo "✅ Created ecsTaskExecutionRole"
fi

# Task role
if aws iam get-role --role-name ecsTaskRole &> /dev/null; then
    echo "✅ ecsTaskRole already exists"
else
    aws iam create-role --role-name ecsTaskRole --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {"Service": "ecs-tasks.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }
      ]
    }' > /dev/null
    echo "✅ Created ecsTaskRole"
fi

# Create ECS service-linked role (required for load balancer integration)
echo
echo "🔗 Creating ECS service-linked role..."
if aws iam get-role --role-name AWSServiceRoleForECS &> /dev/null; then
    echo "✅ ECS service-linked role already exists"
else
    aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com > /dev/null 2>&1 || echo "✅ ECS service-linked role already exists (or creation not needed)"
    echo "✅ ECS service-linked role configured"
fi

# Create .env file
echo
echo "📄 Creating .env file..."
cat > .env << EOF
# Application Configuration
APP_NAME=$PROJECT_NAME
APP_VERSION=1.0.0
DEBUG=false

# AWS Configuration
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI

# ECS Configuration
ECS_CLUSTER_NAME=$CLUSTER_NAME
ECS_SERVICE_NAME=$SERVICE_NAME

# Environment
ENVIRONMENT=$ENVIRONMENT

# Security Configuration
API_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
ENABLE_API_KEY_AUTH=true
EOF

echo "✅ Created .env file"

# Now call the template substitution script
echo
echo "🔧 Configuring template files..."
./scripts/configure-templates.sh

echo
echo "🎉 Setup complete!"
echo
echo "📋 Next steps:"
echo "1. Build and deploy: ./scripts/deploy.sh"
echo "2. Access your API at: http://$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)"
echo
echo "💡 Your infrastructure is ready! The first deployment will create the ECS service."