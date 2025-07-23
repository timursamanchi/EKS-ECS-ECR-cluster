#!/bin/bash

set -e

echo "🧹 Starting ECS cleanup..."

# Environment setup (redefine if needed)
CLUSTER_NAME=quote-app-cluster
BACKEND_SERVICE=quote-backend-service
FRONTEND_SERVICE=quote-frontend-service
EXEC_ROLE=ecsTaskExecutionRole

# 1. Delete ECS services (force deregistration)
aws ecs update-service --cluster $CLUSTER_NAME --service $BACKEND_SERVICE --desired-count 0 || true
aws ecs update-service --cluster $CLUSTER_NAME --service $FRONTEND_SERVICE --desired-count 0 || true

sleep 5  # Let tasks drain

aws ecs delete-service --cluster $CLUSTER_NAME --service $BACKEND_SERVICE --force || true
aws ecs delete-service --cluster $CLUSTER_NAME --service $FRONTEND_SERVICE --force || true

# 2. Delete ECS cluster
aws ecs delete-cluster --cluster $CLUSTER_NAME || true

# 3. Optional: Deregister task definitions
aws ecs list-task-definitions | grep quote-backend-task | while read arn; do aws ecs deregister-task-definition --task-definition "$arn"; done
aws ecs list-task-definitions | grep quote-frontend-task | while read arn; do aws ecs deregister-task-definition --task-definition "$arn"; done

# 4. IAM role cleanup
aws iam detach-role-policy --role-name $EXEC_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy || true
aws iam delete-role --role-name $EXEC_ROLE || true

# 5. Delete security group
echo "🔍 Looking up Security Group ID..."
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=quote-sg --query "SecurityGroups[0].GroupId" --output text)
aws ec2 delete-security-group --group-id $SG_ID || true

# 6. Delete route table + route
VPC_ID=$(aws ec2 describe-vpcs --filters Name=cidr,Values=10.0.0.0/16 --query "Vpcs[0].VpcId" --output text)
RT_ID=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" --output text)
aws ec2 delete-route-table --route-table-id $RT_ID || true

# 7. Detach and delete IGW
IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[0].InternetGatewayId" --output text)
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID || true
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID || true

# 8. Delete subnet
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[0].SubnetId" --output text)
aws ec2 delete-subnet --subnet-id $SUBNET_ID || true

# 9. Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID || true

echo "✅ Cleanup complete."
