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
  --no-cache \
  --push \
  -t 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-frontend \
  ./quote-frontend


docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --no-cache \
  --push \
  -t 040929397520.dkr.ecr.eu-west-1.amazonaws.com/quote-backend \
  ./quote-backend

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
2️⃣ Run Inside ECS (Cloud Test)

This means:

    Launching a Fargate service

    Assigning a public IP

    Accessing via external IP (no localhost here)

We’ll do this once you're ready to “walk” into cloud networking with ECS step-by-step.

### i- create an ECS cluster
```
aws ecs create-cluster --cluster-name quote-cluster
```

### ii- Create the Fargate Service
```
aws ecs create-service \
  --cluster quote-cluster \
  --service-name quote-service \
  --task-definition quote-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration '{
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxxxxxxx"],         # Your public subnet(s)
      "securityGroups": ["sg-xxxxxxxx"],       # Must allow inbound 8080 or 80
      "assignPublicIp": "ENABLED"
    }
  }'
```

### to creat the aws infrastructure

#### create a vpc and tag it. 
```
  aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ecs-test-vpc}]'
```

#### create a public subnet and tag it - and then modify it for ingress rules ports 80 for the frontend and 8080 for the backend
```
aws ec2 create-subnet \
  --vpc-id <your-vpc-id> \
  --cidr-block 10.0.1.0/24 \
  --availability-zone eu-west-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-pub}]'
```
#### modify to assign a public IP on launch
```
aws ec2 modify-subnet-attribute \
  --subnet-id <your-subnet-id> \
  --map-public-ip-on-launch

```
#### create security groups 
```
aws ec2 create-security-group \
  --group-name quote-security-group \
  --description "Allow inbound HTTP traffic" \
  --vpc-id <your-vpc-id>
```
#### add port 80
```
aws ec2 authorize-security-group-ingress \
  --group-id <your-security-group-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

```

#### add port 8080
```
aws ec2 authorize-security-group-ingress \
  --group-id <your-security-group-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0

```
🔧 Plug Into Your ECS Service Command

Replace:

    "subnets": ["subnet-xxxxxxxx"] → with your public subnet ID. 

    "securityGroups": ["sg-xxxxxxxx"] → with the new security group ID. 