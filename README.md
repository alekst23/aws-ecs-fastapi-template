# AWS ECS API Template

A **turnkey template** for deploying containerized Python FastAPI applications to AWS ECS with zero manual configuration.

## Overview

This template automatically creates all AWS infrastructure and deploys your FastAPI application to ECS in just a few commands. No manual variable substitution or AWS resource management required.

**What it creates for you:**
- **FastAPI Application**: Modern Python web framework with automatic API documentation
- **Docker Container**: Production-optimized multi-stage build
- **AWS Infrastructure**: ECS cluster, ECR repository, load balancer, security groups, IAM roles
- **Automated Deployment**: One-command deployment with zero downtime updates

## Tech Stack

- **Python 3.11+** with **FastAPI** and **Poetry**
- **Docker** for containerization
- **AWS ECS Fargate** for container orchestration  
- **AWS ECR** for container registry
- **AWS Application Load Balancer** for traffic routing

## 🚀 Quick Start (3 Steps)

### Prerequisites
- AWS CLI installed and configured (`aws configure`)
- Docker installed
- `jq` command-line tool (`brew install jq` or `apt-get install jq`)

### Required AWS Permissions

Your AWS CLI user needs the following IAM permissions for this template to work:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DescribeRepositories",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "ecr:DescribeImages",
                "ecs:CreateCluster",
                "ecs:DescribeClusters",
                "ecs:CreateService",
                "ecs:DescribeServices",
                "ecs:UpdateService",
                "ecs:RegisterTaskDefinition",
                "ecs:DescribeTaskDefinition",
                "ecs:TagResource",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:CreateListener",
                "iam:CreateRole",
                "iam:GetRole",
                "iam:AttachRolePolicy",
                "iam:CreateServiceLinkedRole",
                "sts:GetCallerIdentity",
                "logs:CreateLogGroup",
                "logs:DescribeLogStreams",
                "logs:GetLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
```

**Note:** You can create a custom IAM policy with these permissions and attach it to your AWS CLI user, or use the `PowerUserAccess` managed policy (which includes these and more permissions).

### 1. Clone and Setup
```bash
git clone <your-template-repo> my-new-api
cd my-new-api

# Run the interactive setup (creates ALL AWS resources automatically)
./scripts/setup.sh
```

The setup script will:
- ✅ Create ECR repository
- ✅ Create ECS cluster  
- ✅ Set up VPC networking (subnets, security groups)
- ✅ Create Application Load Balancer with target group
- ✅ Create required IAM roles
- ✅ Generate `.env` file with all values
- ✅ Configure all template files automatically

### 2. Deploy
```bash
# Build, push, and deploy to ECS (creates service on first run)
./scripts/deploy.sh
```

### 3. Access Your API
Your API will be available at the load balancer URL shown in the setup output.

**API Documentation:**
- Swagger UI: `http://your-alb-url/docs`
- ReDoc: `http://your-alb-url/redoc`
- Health Check: `http://your-alb-url/health`

## 📁 Project Structure

```
├── app/
│   ├── main.py              # FastAPI application entry point
│   ├── api/
│   │   └── routes.py        # API routes (customize here)
│   └── core/
│       └── config.py        # Application configuration
├── aws/
│   ├── task-definition.json # ECS task definition (auto-configured)
│   └── service.json         # ECS service config (auto-configured)
├── scripts/
│   ├── setup.sh            # 🌟 Interactive setup (creates all AWS resources)
│   ├── deploy.sh           # Build and deploy
│   ├── build-and-push.sh   # Build and push to ECR
│   ├── create-service.sh   # Create ECS service
│   ├── configure-templates.sh  # Configure template files
│   └── validate.sh         # Validate configuration
├── Dockerfile              # Multi-stage production build
├── pyproject.toml          # Poetry dependencies
├── .env.example           
├── .gitignore
└── README.md
```

## 🔧 Available Scripts

| Script | Purpose |
|--------|---------|
| `./scripts/setup.sh` | **One-time setup** - Creates all AWS infrastructure and configures templates |
| `./scripts/deploy.sh` | **Deploy updates** - Build, push, and update ECS service |
| `./scripts/validate.sh` | **Validate setup** - Check that all resources exist and are configured |
| `./scripts/build-and-push.sh` | **Build only** - Build and push Docker image to ECR |

## 🎯 Customization

### 1. Customize Your API
- **Routes**: Edit `app/api/routes.py` with your endpoints
- **Main App**: Modify `app/main.py` for app-level configuration  
- **Dependencies**: Add packages to `pyproject.toml`

### 2. Environment Configuration
The setup script creates a `.env` file automatically. You can modify:
```bash
# Application settings
APP_NAME=my-api
DEBUG=false

# Environment
ENVIRONMENT=dev  # or staging, prod
```

### 3. Infrastructure Scaling
To change CPU/memory after setup, edit `aws/task-definition.json`:
```json
"cpu": "512",     # 256, 512, 1024, 2048, 4096
"memory": "1024"  # 512, 1024, 2048, 4096, 8192
```

Then redeploy: `./scripts/deploy.sh`

### 4. Service Scaling
Change the number of running containers:
```bash
aws ecs update-service \
  --cluster $ECS_CLUSTER_NAME \
  --service $ECS_SERVICE_NAME \
  --desired-count 4
```

## 🛠 Development Workflow

### Local Development
```bash
# Install dependencies
poetry install

# Run locally
poetry run dev
# API available at http://localhost:8000
```

### Testing Docker Build
```bash
# Build and test locally
docker build -t my-api .
docker run -p 8000:8000 my-api
```

### Deploy Updates
```bash
# After making code changes
./scripts/deploy.sh
# Builds new image, pushes to ECR, updates ECS service
```

## 🚨 Troubleshooting

### Setup Issues
```bash
# Validate your configuration
./scripts/validate.sh

# Check AWS credentials
aws sts get-caller-identity

# Re-run setup if needed
./scripts/setup.sh
```

### Deployment Issues
```bash
# Check ECS service status
aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME

# Check logs
aws logs tail /ecs/$APP_NAME --follow
```

### Common Fixes
- **"Repository does not exist"**: Run `./scripts/setup.sh` first
- **"Service not found"**: First deployment creates the service automatically
- **"Task stopped"**: Check CloudWatch logs for startup errors
- **"Health check failing"**: Ensure your app responds to `/health` endpoint

## 🔍 What Gets Created

The setup script creates these AWS resources:

| Resource | Purpose | Name Pattern |
|----------|---------|--------------|
| ECS Cluster | Container orchestration | `{project}-cluster` |
| ECR Repository | Container images | `{project}` |
| Security Group | Network access | `{project}-ecs-sg` |
| Load Balancer | Traffic routing | `{project}-alb` |
| Target Group | Health checks | `{project}-tg` |
| IAM Roles | ECS permissions | `ecsTaskRole`, `ecsTaskExecutionRole` |
| CloudWatch Logs | Application logs | `/ecs/{project}` |

## 📊 Monitoring

- **Logs**: CloudWatch Logs at `/ecs/{your-project-name}`
- **Metrics**: ECS service metrics in CloudWatch
- **Health**: Built-in health check at `/health` endpoint
- **Scaling**: Auto-scaling based on CPU/memory (configurable)

## 💰 Cost Optimization

- **Fargate Spot**: Consider spot instances for dev environments
- **Right-sizing**: Start with 256 CPU / 512MB memory, scale as needed
- **Log Retention**: Set CloudWatch log retention periods
- **Load Balancer**: Use single ALB for multiple services

## 🔒 Security Features

- **Non-root container**: Docker runs as non-root user
- **Security groups**: Restricts network access to port 8000 only
- **IAM roles**: Least-privilege access for ECS tasks
- **HTTPS ready**: Add SSL certificate to load balancer for production

## 📋 Migration from Other Templates

If you have an existing project:

1. **Copy your code** to `app/` directory
2. **Update dependencies** in `pyproject.toml`
3. **Run setup**: `./scripts/setup.sh`
4. **Deploy**: `./scripts/deploy.sh`

## 🤝 Contributing

Improvements welcome! This template aims to be the easiest way to deploy FastAPI apps to AWS ECS.

## 📄 License

MIT License - use this template freely for your projects.