#! /bin/bash

#still WIP state... needs work
printf '%s\n' "----------------------"
printf '%s\n' "Terminating environment"
printf '%s\n' "----------------------"
# check for variabels
#-----------------------
. 00_define_vars.sh

varsok=true
#if  [ -z "${AWS_REGION}" ]; then echo AWS_REGION must be set && varsok=false; fi
if  [ -z "${AWS_PROJECT}" ]; then echo AWS_PROJECT must be set && varsok=false; fi
if  [ "$varsok" = false ]; then exit ; fi

printf '%s\n' "Getting region from AWS configure"
export AWS_REGION=`aws configure get region`
echo AWS_REGION= $AWS_REGION

#delete deployed apps
printf "%s\n" "Removing Deployments on EKS cluster"
kubectl delete deployment $APP1
kubectl delete deployment $APP2
kubectl delete deployment $APP3

# Delete ECR repos
printf "%s\n" "Checking ECR Repositories"
aws_ecr_repos=(`aws ecr describe-repositories --region ${AWS_REGION} | jq -r '.repositories[].repositoryName'`)
aws_ecr_repo=''
for i in "${!aws_ecr_repos[@]}"; do
  #printf "%s" "Repo $i =  ${aws_ecr_repos[$i]}"
  aws_ecr_repo=`echo ${1} | awk '{ print tolower($0) }'`
  if [[ "${aws_ecr_repos[$i]}" =~ "${AWS_PROJECT}" ]]; then
      printf "%s\n" "Deleting ECR repository: ${aws_ecr_repos[$i]}"
      aws_ecr_repo_exists="true"
      DUMMY=`aws ecr delete-repository --repository-name ${aws_ecr_repos[$i]} --region ${AWS_REGION} --force`
  fi
done

# Delete CodeCommit repos
printf "%s\n" "Checking CodeCommit Repositories"
aws_cc_repos=(`aws codecommit list-repositories --region $AWS_REGION | jq -r '.repositories[].repositoryName'`)
aws_cc_repo=''
for i in "${!aws_cc_repos[@]}"; do
  #printf '%s\n' "Checking CC Repo $i =  ${aws_cc_repos[$i]} ..........Comparing with ${1}"
  if [[ "${aws_cc_repos[$i]}" =~ "${AWS_PROJECT}" ]]; then
      printf "%s\n" "Deleting CodeCommit Repo "${aws_cc_repos[$i]}
      DUMMY=`aws codecommit delete-repository --repository-name ${aws_cc_repos[$i]} --region ${AWS_REGION}`
    fi
done

# Delete Cloudformation Stacks
printf "%s \n" "Checking CloudFormation Pipeline Stacks..."
aws_stack=""
aws_stacks=(`aws cloudformation describe-stacks --output json --region $AWS_REGION| jq -r '.Stacks[].StackName'` )
for i in "${!aws_stacks[@]}"; do
  #printf "%s\n" "stack $i =  ${aws_stacks[$i]}"
  if [[ "${aws_stacks[$i]}" =~ "${AWS_PROJECT}"  && "${aws_stacks[$i]}" =~ "Pipeline" ]]; then
    printf "%s \n" "  Deleting CloudFormation Pipeline Stack  ${aws_stacks[$i]}"
    aws cloudformation delete-stack --stack-name ${aws_stacks[$i]} --region ${AWS_REGION}
    aws cloudformation wait stack-delete-complete --stack-name ${aws_stacks[$i]}  --region ${AWS_REGION}
  fi
done
printf "\n"


#TBD: delete log groups

# delete cluster
printf "%s \n" "Checking EKS cluster..."
aws_eks_clusters=(`eksctl get clusters -o json | jq -r '.[].name'`)
for i in "${!aws_eks_clusters[@]}"; do
  #printf "%s" "cluster $i =  ${aws_eks_clusters[$i]}.........."
  if [[ "${aws_eks_clusters[$i]}" =~ "${AWS_PROJECT}" ]]; then
       printf "%s\n" "  Deleting EKS cluster: ${AWS_PROJECT}"
       printf "%s\n" "  Please be patient, this can take up to 30 minutes... (started at:`date`)"
      if [ -s  "${AWS_PROJECT}EksCluster.yml" ]; then
        #eksctl delete cluster -f ${AWS_PROJECT}EksCluster.yml
        starttime=`date +%s`
        eksctl delete cluster ${AWS_PROJECT} --wait
        sleep 30  #giving the delete cluster process a bit more time
        endtime=`date +%s`
        printf '%s\n' "  Elapsed time: $((($endtime-$starttime)/60)) minutes"
      else
        printf '%s \n' "  PANIC: eks cluster with name ${AWS_PROJECT} exists, but file \"${AWS_PROJECT}EksCluster.yml\" does not"
        printf '%s \n' "This situation should not exist.  Manual cleanup is required"
      fi
       printf "%s\n" "Please be patient, this can take up to 30 minutes... (started at:`date`)"
  fi
done


# Cleaning up project VPC, starting with its dependencies
aws_vpc_ids=(`aws ec2 describe-vpcs | jq -r ".Vpcs[].VpcId"`)
#find Project VPCs
for i in "${!aws_vpc_ids[@]}"; do
  #printf "%s\n" "vpc $i = ${aws_vpc_ids[$i]}.........."
  aws_vpc_tags=`aws ec2 describe-vpcs --vpc-ids ${aws_vpc_ids[$i]} | jq -r '.Vpcs[].Tags'`  #no array needed here; just get thm all in one string
  #printf "%s\n" "${aws_vpc_tags}"
  if [[ ${aws_vpc_tags} =~ ${AWS_PROJECT} ]];then
    printf "%s\n" "Found VPC belonging to project: ${aws_vpc_ids[$i]}"
    aws_attachment_ids=(`aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${aws_vpc_ids[$i]} | jq -r '.NetworkInterfaces[].Attachment.AttachmentId'`)
      printf "%s\n" "Found aws_attachment_ids: ${aws_attachment_ids[@]}"
    for j in "${!aws_attachment_ids[@]}"; do
        printf "%s\n" "Found attachment ID ${aws_attachment_ids[$j]}"
      if [[ "${aws_attachment_ids[$j]}" != "null" &&  "${aws_attachment_ids[$j]}" != "" ]];then
        printf "%s\n" "Detaching ENI with attachment_id ${aws_attachment_ids[$j]}"
        aws ec2 detach-network-interface --attachment-id  ${aws_attachment_ids[$j]}
        #get ENI ID
      else
        printf "%s\n" "No Elastic Network Interface attached"
      fi
    done
    aws_ENI_ids=(`aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${aws_vpc_ids[$i]} | jq -r '.NetworkInterfaces[].NetworkInterfaceId'`)
    for j in "${!aws_ENI_ids[@]}"; do
        printf "%s\n" "Deleting ENI: ${aws_ENI_ids[$j]}"
        aws ec2 delete-network-interface --network-interface-id ${aws_ENI_ids[$j]}
    done
    #delete Load Balancer
    aws_lb=(`aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[]|select(.VPCId|test(\"${aws_vpc_ids[$i]}\"))|.LoadBalancerName"`)

    for j in "${!aws_lb[@]}"; do
      if [[ "${aws_lb[$j]}" != "null" &&  "${aws_lb[$j]}" != "" ]];then
        printf "%s\n" "Deleting Load Balancer: xxxxx${aws_lb[$j]}xxxxxxxxx"
        aws elb delete-load-balancer --load-balancer-name ${aws_lb[$j]}
      else
        printf "%s\n" "No Load Balancer attached"
      fi
    done

    #delete nat gateway
    natgw_id=`aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${aws_vpc_ids[$i]}"  | jq -r ".NatGateways[].NatGatewayId"`
    if [[ "${natgw_id}" != "null" &&  "${natgw_id}" != "" ]];then
      printf "%s\n" "Deleting NAT Gateway: ${natgw_id}"
      aws ec2 delete-nat-gateway --nat-gateway-id ${natgw_id}
    else
      printf "%s\n" "No NAT Gateway attached"
    fi

    #delete internet gateway
    igw_id=`aws ec2 describe-internet-gateways | jq -r ".InternetGateways[]|
    select(.Attachments[].VpcId|test(\"${aws_vpc_ids[$i]}\"))|.InternetGatewayId"`
    if [[ "${igw_id}" != "null" &&  "${igw_id}" != "" ]];then
      printf "%s\n" "Detaching Internet Gateway: ${igw_id}"
      aws ec2 detach-internet-gateway --internet-gateway-id ${igw_id}  --vpc-id=${aws_vpc_ids[$i]}
      printf "%s\n" "Deleting Internet Gateway: ${igw_id}"
      aws ec2 delete-internet-gateway --internet-gateway-id ${igw_id}
    else
      printf "%s\n" "No Internet Gateway attached"
    fi

    #delete security groups
    printf "%s\n" "Checking Security Groups"
    aws_sg_ids=(`aws ec2 describe-security-groups --filters Name=vpc-id,Values=${aws_vpc_ids[$i]} | jq -r '.SecurityGroups[].GroupId'`)
    for j in "${!aws_sg_ids[@]}"; do
        if [[ "`aws ec2 describe-security-groups --filters Name=group-id,Values=${aws_sg_ids[$j]} | jq -r '.SecurityGroups[].GroupName'`" != "default" ]];then
          printf "%s\n" "Deleting Security Group: ${aws_sg_ids[$j]}"
          aws ec2 delete-security-group --group-id ${aws_sg_ids[$j]}
        fi
    done


    #delete Subnets
    printf "%s\n" "Checking Subnets"
    aws_sn_ids=(`aws ec2 describe-subnets --filters Name=vpc-id,Values=${aws_vpc_ids[$i]} | jq -r '.Subnets[].SubnetId'`)
    for j in "${!aws_sn_ids[@]}"; do
        if [[ "`aws ec2 describe-subnets --filters Name=subnet-id,Values=${aws_sn_ids[j]} | jq -r '.Subnets[].DefaultForAz'`" != "true" ]];then
          printf "%s\n" "Deleting Subnet: ${aws_sn_ids[$j]}"
          aws ec2 delete-subnet --subnet-id ${aws_sn_ids[$j]}
        fi
    done

    printf "%s\n" "Checking dependencies of VPC: ${aws_vpc_ids[$i]}"
    vpc=${aws_vpc_ids[$i]}
    printf "%s\n" "Checking dependencies of VPC: $vpc"
    aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$vpc | grep InternetGatewayId
    aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$vpc | grep SubnetId
    aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$vpc | grep RouteTableId
    aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$vpc | grep NetworkAclId
    aws ec2 describe-vpc-peering-connections --filters 'Name=requester-vpc-info.vpc-id,Values='$vpc | grep VpcPeeringConnectionId
    aws ec2 describe-vpc-endpoints --filters 'Name=vpc-id,Values='$vpc | grep VpcEndpointId
    aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$vpc | grep NatGatewayId
    aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$vpc | grep GroupId
    aws ec2 describe-instances --filters 'Name=vpc-id,Values='$vpc | grep InstanceId
    aws ec2 describe-vpn-connections --filters 'Name=vpc-id,Values='$vpc | grep VpnConnectionId
    aws ec2 describe-vpn-gateways --filters 'Name=attachment.vpc-id,Values='$vpc | grep VpnGatewayId
    aws ec2 describe-network-interfaces --filters 'Name=vpc-id,Values='$vpc | grep NetworkInterfaceId


    printf "%s\n" "Deleting VPC: ${aws_vpc_ids[$i]}  (hopefully)"
    aws ec2 delete-vpc --vpc-id ${aws_vpc_ids[$i]}
  fi
  printf "%s\n" "---"
done

#the EKS cluster should already have been deleted  (in reality it is sometimes not)
aws_eks_clusters=(`eksctl get clusters -o json | jq -r '.[].name'`)
for i in "${!aws_eks_clusters[@]}"; do
  printf "%s" "cluster $i =  ${aws_eks_clusters[$i]}.........."
  if [[ "${aws_eks_clusters[$i]}" =~ "${AWS_PROJECT}"  && "${aws_eks_clusters[$i]}" =~ "Pipeline" ]]; then
      printf "%s\n" "Deleting EKS cluster: ${AWS_PROJECT}"
      if [ -s  "${AWS_PROJECT}EksCluster.yml" ]; then
        #eksctl delete cluster -f ${AWS_PROJECT}EksCluster.yml
        eksctl delete cluster ${AWS_PROJECT}
        sleep 30  #giving the delete cluster process a bit more time
      else
        printf '%s \n' "PANIC: eks cluster with name ${AWS_PROJECT} exists, but file \"${AWS_PROJECT}EksCluster.yml\" does not"
        printf '%s \n' "This situation should not exist.  Manual cleanup is required"
      fi
  else
      printf "%s\n" ""
  fi
done


printf "%s\n" "Checking CloudFormation EKS nodegroup Stack"
aws_stack=""
aws_stacks=(`aws cloudformation describe-stacks --output json --region $AWS_REGION| jq -r '.Stacks[].StackName'` )
for i in "${!aws_stacks[@]}"; do
  # printf "%s\n" "stack $i =  ${aws_stacks[$i]}"
  if [[ "${aws_stacks[$i]}" =~ "eksctl-${AWS_PROJECT}-nodegroup" ]]; then
    printf "%s\n" "Deleting CloudFormation Stack:  ${aws_stacks[$i]}"
    starttime=`date +%s`
    printf "%s\n" "Please be patient, this can take up to 30 minutes... (started at:`date`)"
    aws cloudformation delete-stack --stack-name ${aws_stacks[$i]} --region ${AWS_REGION}
    aws cloudformation wait stack-delete-complete --stack-name ${aws_stacks[$i]}  --region ${AWS_REGION}
    endtime=`date +%s`
    printf '%s\n' "Elapsed time: $((($endtime-$starttime)/60)) minutes"
  fi
done

printf "%s\n" "Checking CloudFormation EKS Stack"
aws_stack=""
aws_stacks=(`aws cloudformation describe-stacks --output json --region $AWS_REGION| jq -r '.Stacks[].StackName'` )
for i in "${!aws_stacks[@]}"; do
  # printf "%s\n" "stack $i =  ${aws_stacks[$i]}"
  if [[ "${aws_stacks[$i]}" =~ "eksctl-${AWS_PROJECT}-cluster" ]]; then
    printf "%s\n" "Deleting CloudFormation Stack:  ${aws_stacks[$i]}"
    starttime=`date +%s`
    printf "%s\n" "Please be patient, this can take up to 30 minutes... (started at:`date`)"
    aws cloudformation delete-stack --stack-name ${aws_stacks[$i]} --region ${AWS_REGION}
    aws cloudformation wait stack-delete-complete --stack-name ${aws_stacks[$i]}  --region ${AWS_REGION}
    endtime=`date +%s`
    printf '%s\n' "Elapsed time: $((($endtime-$starttime)/60)) minutes"
  fi
done



#cleanup codepipelineartifactbuckets
buckets=(`aws s3api list-buckets --region ${AWS_REGION}| jq -r '.Buckets[].Name' ` )
for i in "${!buckets[@]}"; do
  #printf '%s\n' "Bucket ${i} = ${buckets[${i}]}"
  if [[ "${buckets[${i}]}" =~ "codepipelineartifact" &&  "${buckets[${i}]}" =~ "${AWS_PROJECT}" ]]; then
      printf "%s\n"  "Deleting codepipelineartifactbucket: ${buckets[${i}]}"
      aws s3 rb s3://${buckets[${i}]} --force
      #aws s3api  delete-bucket  --bucket ${buckets[$i]}  --region ${AWS_REGION}
  fi
done

#cleaning up local files
[ -e ${AWS_PROJECT}EksCluster.yml ] && rm ${AWS_PROJECT}EksCluster.yml
[ -e ${AWS_PROJECT}${APP1}Pipeline.yml ] && rm ${AWS_PROJECT}${APP1}Pipeline.yml
[ -e ${AWS_PROJECT}${APP2}Pipeline.yml ] && rm ${AWS_PROJECT}${APP2}Pipeline.yml
[ -e ${AWS_PROJECT}${APP3}Pipeline.yml ] && rm ${AWS_PROJECT}${APP3}Pipeline.yml
[ -e req.conf ] && rm req.conf
[ -e k8s.key ] && rm k8s.key
[ -e k8s.crt ] && rm k8s.crt
[ -e overrides.yml ] && rm overrides.yml
[ -e cloudOneCredentials ] && rm cloudOneCredentials
#echo About to delete ~/environment/${APP1}/
#rm -rf ~/environment/${APP1}/


printf "%s\n" "Deleting Roles and Instance-Profiles"
AWS_ROLES=(`aws iam list-roles | jq -r '.Roles[].RoleName ' | grep ${AWS_PROJECT} `)
for i in "${!AWS_ROLES[@]}"; do
  if [[ "${AWS_ROLES[$i]}" =~ "${AWS_PROJECT}" ]]; then
     printf "%s\n" "Role $i =  ${AWS_ROLES[$i]}.........."
     #printf "%s\n" "Getting AWS_POLICIES"
     AWS_POLICIES=(`aws iam list-role-policies --role-name ${AWS_ROLES[$i]} | jq -r '.PolicyNames[]'`)
      #              aws iam list-role-policies --role-name ${AWS_ROLES[$i]}
     printf "%s\n" "AWS_POLICIES= $AWS_POLICIES"
     for j in "${!AWS_POLICIES[@]}"; do
       printf "%s\n" "  Policy $j =  ${AWS_POLICIES[$j]}"
      aws iam detach-role-policy --role-name ${AWS_ROLES[$i]} --policy-name ${AWS_POLICIES[$j]}
        aws iam delete-role-policy --role-name ${AWS_ROLES[$i]} --policy-name ${AWS_POLICIES[$j]}
     done
     #printf "%s\n" "Getting instance Profiles"
     #printf "%s\n" "Analyzing Instance Profiles for Role: ${AWS_ROLES[$i]}"
     AWS_PROFILES=(`aws iam list-instance-profiles-for-role --role-name ${AWS_ROLES[$i]} | jq -r '.InstanceProfiles[].InstanceProfileName'`)
     printf "%s\n" "AWS_PROFILES = $AWS_PROFILES"
     for k in "${!AWS_PROFILES[@]}"; do
       printf "%s\n" "  Profile $k =  ${AWS_PROFILES[$k]}"
       aws iam remove-role-from-instance-profile --role-name ${AWS_ROLES[$i]} --instance-profile-name ${AWS_PROFILES[$j]}
       aws iam delete-instance-profile --instance-profile-name ${AWS_PROFILES[$j]}
     done
     aws iam delete-role  --role-name ${AWS_ROLES[$i]}
  fi
done
#aws iam list-roles | jq -r '.Roles[].RoleName ' | grep cloudone

#TODO: delete Policy
