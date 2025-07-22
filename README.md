# EKS-ECS-ECR-cluster
K0s cluster on AWS using EKS, ECS, ESR



# 🚀 Full ECS + ECR Deployment Steps
    Step	Task. 
    1️⃣	Create ECR repositories. 
    2️⃣	Authenticate Docker to ECR. 
    3️⃣	Build and push multi-arch Docker images. 
    4️⃣	Create IAM execution role for ECS tasks. 
    5️⃣	Define ECS Fargate-compatible task definition. 
    6️⃣	Launch ECS service on Fargate. 

```
aws ecr create-repository --repository-name quote-frontend
aws ecr create-repository --repository-name quote-backend
```
## get my aws account number
```
aws sts get-caller-identity --query Account --output text
```

## authenicate and link you dockerhub account to your aws account
```
aws ecr get-login-password | docker login \
  --username AWS \
  --password-stdin 040929397520.dkr.ecr.eu-west-1.amazonaws.com
```

## build and push multi arch image to docker/ecr
```
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-frontend ./quote-frontend

timursamanchi@Timurs-Air EKS-ECS-ECR % docker buildx build \
  --platform linux/amd64 \
  --push \
  -t 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-backend ./quote-backend
```
## Create ECS Execution Role
```
aws iam create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'
```
## Attach ECS task execution policy
```
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```
## register task-definition with ECS
```
  aws ecs register-task-definition --cli-input-json file://quote-task-def.json
```

## 1) Run Locally (Quick Test)
```
docker pull 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-backend:latest
docker run -p 8080:8080 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-backend
curl http://localhost:8080


docker pull 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-frontend:latest
docker run -p 80:80 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-frontend
docker run -d --name quote-frontend --link quote-backend -p 80:80 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-frontend:latest
http://localhost

```
## 2) Run inside ECS (cloud test)