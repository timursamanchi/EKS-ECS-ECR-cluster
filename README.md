# 🚀 Full ECS + ECR Deployment Steps

    Step	Task. 
    1️⃣	Create ECR repositories. 
    2️⃣	Authenticate Docker to ECR. 
    3️⃣	Build and push multi-arch Docker images. 
    4️⃣	Create IAM execution role for ECS tasks. 
    5️⃣	Define ECS Fargate-compatible task definition. 
    6️⃣	Launch ECS service on Fargate. 


## ✅ Set up the underpinning aws infastructure 

sets up temporary environment variables in your current shell session.
```
export AWS_REGION=eu-west-1
export VPC_CIDR=10.0.0.0/16
export SUBNET_CIDR=10.0.1.0/24
export CLUSTER_NAME=quote-app-cluster
export BACKEND_PORT=8080
export FRONTEND_PORT=80
```

✅ to Make Them Persistent If you want these to persist between terminal sessions, you can add the export lines to your shell config file Zsh: ~/.zshrc
```
echo 'export AWS_REGION=eu-west-1' >> ~/.bashrc
source ~/.bashrc
```

✅ How to Check They're Set: After running the export commands, 

run:
```
echo $AWS_REGION
echo $VPC_CIDR
```

You should see:
```
eu-west-1
10.0.0.0/16
```

## 1. 🧱 Create VPC networking (or use existing)

we'll need:  
    - A vpc and one or more Subnet IDs. 

    - A Security Group. 
    
    - The subnets must be in public subnets with Internet Gateway access, and SG must allow inbound HTTP (80) and backend port (8080) if testing directly.  

### 1.1- create a vpc and tag it. 
```
# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=ecs-test-vpc
```

### 1.2- create a public subnet and tag it 
```
# Create Subnet
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block $SUBNET_CIDR \
  --availability-zone ${AWS_REGION}a \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value=subnet-pub
```

### 1.3- modify to assign a public IP on launch
```
# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
```

### 1.4- create and attach IGW to VPC
```
# Create Internet Gateway and attach to VPC
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

### 1.5- create Route Table and default route
```
RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_ID
```

### 1.6- 🔐 create security groups - and then modify it for ingress rules ports 80 for the frontend and 8080 for the backend
```
# Create SG
SG_ID=$(aws ec2 create-security-group \
  --group-name quote-sg \
  --description "Allow HTTP ports" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow 80 (frontend)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

# Allow 8080 (backend)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0

```

### 1.7 🤖 IAM Execution Role for ECS Tasks
```
# create IAM ECS Execution Role
aws iam create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "ecs-tasks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach ECS task execution policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

## 🛠️ 2. Task Definitions (Backend + Frontend) - Save each JSON to a file and register.

quote-backend-task.json
```
{
  "family": "quote-backend-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<your-account-id>:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "quote-backend",
      "image": "040929397520.dkr.ecr.eu-west-1.amazonaws.com/aws-quote-backend:latest",
      "portMappings": [{ "containerPort": 8080 }]
    }
  ]
}
```

quote-frontend-task.json
```
{
  "family": "quote-frontend-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<your-account-id>:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "quote-frontend",
      "image": "040929397520.dkr.ecr.eu-west-1.amazonaws.com/aws-quote-frontend:latest",
      "portMappings": [{ "containerPort": 80 }]
    }
  ]
}
```

Register the task definitions
```
aws ecs register-task-definition --cli-input-json file://quote-backend-task.json
aws ecs register-task-definition --cli-input-json file://quote-frontend-task.json

each command will return a task definition arn like so:

arn:aws:ecs:eu-west-1:040929397520:task-definition/quote-backend-task:1
```

## 🧩 2. Create the cluster
```
aws ecs create-cluster --cluster-name quote-app-cluster-copilot

or

aws ecs create-cluster --cluster-name $CLUSTER_NAME
```

## 🚀 3. Create Fargate Services

Backend service
```
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name quote-backend-service \
  --task-definition quote-backend-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}"
```

Frontend service
```
# Frontend service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name quote-frontend-service \
  --task-definition quote-frontend-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}"
```
