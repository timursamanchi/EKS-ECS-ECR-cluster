# #!/bin/bash
# set -e
# echo ""
# echo "🧹 Starting ECS cleanup..."
# echo ""
# CLUSTER_NAME=quote-app-cluster
# BACKEND_SERVICE=quote-backend-service
# FRONTEND_SERVICE=quote-frontend-service
# EXEC_ROLE=ecsTaskExecutionRole

# # 1. Delete ECS services if they exist
# if aws ecs describe-clusters --clusters $CLUSTER_NAME --query "clusters[0].status" --output text 2>/dev/null | grep -q ACTIVE; then
#   echo "ℹ️ Cluster $CLUSTER_NAME found. Proceeding with service cleanup..."
#   aws ecs update-service --cluster $CLUSTER_NAME --service $BACKEND_SERVICE --desired-count 0 || true
#   aws ecs update-service --cluster $CLUSTER_NAME --service $FRONTEND_SERVICE --desired-count 0 || true
#   sleep 5
#   aws ecs delete-service --cluster $CLUSTER_NAME --service $BACKEND_SERVICE --force || true
#   aws ecs delete-service --cluster $CLUSTER_NAME --service $FRONTEND_SERVICE --force || true
#   aws ecs delete-cluster --cluster $CLUSTER_NAME || true
# else
#   echo "⚠️ ECS cluster $CLUSTER_NAME not found. Skipping ECS service and cluster deletion."
# fi

# # 2. Deregister task definitions if they exist
# aws ecs list-task-definitions | grep quote-backend-task | while read arn; do aws ecs deregister-task-definition --task-definition "$arn" || true; done
# aws ecs list-task-definitions | grep quote-frontend-task | while read arn; do aws ecs deregister-task-definition --task-definition "$arn" || true; done

# # 3. IAM Role Cleanup
# if aws iam get-role --role-name $EXEC_ROLE >/dev/null 2>&1; then
#   echo "🔐 Deleting IAM role $EXEC_ROLE"
#   aws iam detach-role-policy --role-name $EXEC_ROLE \
#     --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy || true
#   aws iam delete-role --role-name $EXEC_ROLE || true
# else
#   echo "ℹ️ IAM Role $EXEC_ROLE not found."
# fi

# # 4. Delete security group
# SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=quote-sg --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
# if [[ $SG_ID != "None" && $SG_ID != "" ]]; then
#   echo "🛡️ Deleting security group $SG_ID"
#   aws ec2 delete-security-group --group-id $SG_ID || true
# else
#   echo "⚠️ Security group 'quote-sg' not found."
# fi

# # 5. Delete VPC-related resources based on tag
# VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=ecs-test-vpc --query "Vpcs[0].VpcId" --output text 2>/dev/null)
# if [[ $VPC_ID != "None" && $VPC_ID != "" ]]; then
#   echo "🌐 Tagged VPC $VPC_ID found. Proceeding with route table and IGW cleanup..."

#   RT_ID=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" --output text 2>/dev/null)
#   [[ -n $RT_ID ]] && aws ec2 delete-route-table --route-table-id $RT_ID || echo "⚠️ No non-main route table to delete."

#   IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null)
#   if [[ $IGW_ID != "None" && $IGW_ID != "" ]]; then
#     aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID || true
#     aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID || true
#   else
#     echo "⚠️ No internet gateway attached to $VPC_ID"
#   fi

#   SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[0].SubnetId" --output text 2>/dev/null)
#   [[ $SUBNET_ID != "None" && $SUBNET_ID != "" ]] && aws ec2 delete-subnet --subnet-id $SUBNET_ID || echo "⚠️ No subnet found to delete."

#   # 🔥 DELETE dangling ENIs BEFORE deleting the VPC
#   ENI_IDS=$(aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC_ID --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null)
#   if [[ -n $ENI_IDS ]]; then
#     for eni in $ENI_IDS; do
#       echo "❌ Deleting network interface $eni"
#       aws ec2 delete-network-interface --network-interface-id $eni || true
#     done
#   fi

#   # ✅ Release Elastic IPs
#   EIP_ALLOCATIONS=$(aws ec2 describe-addresses --query "Addresses[?VpcId=='$VPC_ID'].AllocationId" --output text 2>/dev/null)
#   if [[ -n $EIP_ALLOCATIONS ]]; then
#     for alloc in $EIP_ALLOCATIONS; do
#       echo "❎ Releasing Elastic IP $alloc"
#       aws ec2 release-address --allocation-id $alloc || true
#     done
#   fi

#   # ✅ Delete NAT Gateways
#   NAT_GWS=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --query "NatGateways[].NatGatewayId" --output text 2>/dev/null)
#   if [[ -n $NAT_GWS ]]; then
#     for nat in $NAT_GWS; do
#       echo "🚪 Deleting NAT Gateway $nat"
#       aws ec2 delete-nat-gateway --nat-gateway-id $nat || true
#     done
#     echo "🕒 Waiting for NAT Gateway deletion..."
#     sleep 20
#   fi

#   # ✅ Delete VPC endpoints
#   VPCE_IDS=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID --query "VpcEndpoints[].VpcEndpointId" --output text 2>/dev/null)
#   if [[ -n $VPCE_IDS ]]; then
#     echo "🧼 Deleting VPC endpoints"
#     aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $VPCE_IDS || true
#   fi

#   # ✅ Delete VPC peering connections
#   PEERING_IDS=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?RequesterVpcInfo.VpcId=='$VPC_ID'].VpcPeeringConnectionId" --output text 2>/dev/null)
#   if [[ -n $PEERING_IDS ]]; then
#     for peer in $PEERING_IDS; do
#       echo "🔗 Deleting VPC peering connection $peer"
#       aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $peer || true
#     done
#   fi

#   # ✅ Delete non-default Network ACLs
#   ACL_IDS=$(aws ec2 describe-network-acls --filters Name=vpc-id,Values=$VPC_ID --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" --output text 2>/dev/null)
#   if [[ -n $ACL_IDS ]]; then
#     for acl in $ACL_IDS; do
#       echo "🛡️ Deleting non-default Network ACL $acl"
#       aws ec2 delete-network-acl --network-acl-id $acl || true
#     done
#   fi

#   aws ec2 delete-vpc --vpc-id $VPC_ID || echo "⚠️ Could not delete VPC $VPC_ID — check for remaining dependencies."
# else
#   echo "⚠️ No tagged VPC (ecs-test-vpc) found for cleanup."
# fi
# echo ""
# echo "✅ Cleanup complete."


