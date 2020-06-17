#!/bin/bash
printf '%s\n' "-------------------------------"
printf '%s\n' "Creating CodeBuild pipelines "
printf '%s\n' "-------------------------------"

# Sourcing variables
#. ./00_define_vars.sh
. ./cloudOneCredentials.txt

varsok=true
if  [ -z "${DSSC_USERNAME}" ]; then echo DSSC_USERNAME must be set  && varsok=false; fi
if  [ -z "${DSSC_PASSWORD}" ]; then echo DSSC_PASSWORD must be set && varsok=false; fi
if  [ -z "${DSSC_HOST}" ]; then echo DSSC_HOST must be set && varsok=false; fi
if  [ -z "${AWS_REGION}" ]; then echo DSSC_REGION must be set && varsok=false; fi
if  [ -z "${DSSC_REGUSER}" ]; then echo DSSC_REGUSER must be set && varsok=false; fi
if  [ -z "${DSSC_REGPASSWORD}" ]; then echo DSSC_REGPASSWORD must be set && varsok=false; fi
if  [ "$varsok" = false ]; then exit 1 ; fi


function create_pipeline_yaml {
  #$1 = name of the pipeline (${AWS_PROJECT}${APP[$i]})
  LOWER1=`echo ${1} | awk '{ print tolower($0) }'`
  printf '%s\n' "Creating file: ${1}Pipeline.yml "
  ecr_repo_name=`echo ${1}| awk '{print tolower($0)}'`
cat <<EOF>${1}Pipeline.yml
# This file is (re-) generated by code.
# Any manual changes will be overwritten.
---
AWSTemplateFormatVersion: 2010-09-09
Description: pipeline for ${1}

Parameters:

  CodeCommitRepoName:
    Type: String
    Description: The project name, also the CodeCommit Repository name
    Default: ${1}
    MinLength: 1
    MaxLength: 100

  EcrRepoName:
    Type: String
    Description: The name of the ECR Repository
    Default: ${ecr_repo_name}
    MinLength: 1
    MaxLength: 100

  SmartcheckHost:
    Type: String
    Description: Smartcheck host URL
    Default: ${DSSC_HOST}
    MinLength: 1
    MaxLength: 100
    ConstraintDescription: You must enter a Smartcheck host URL

  SmartcheckUser:
    Type: String
    Default: ${DSSC_USERNAME}
    Description: The user for Smartcheck
    MinLength: 1
    MaxLength: 100

  SmartcheckPwd:
    Type: String
    NoEcho: true
    Description: The password for Smartcheck user
    Default: ${DSSC_PASSWORD}
    MinLength: 1
    MaxLength: 100
    ConstraintDescription: You must enter a password for the Smartcheck user

  PreregistryHost:
    Type: String
    Description: Smartcheck host URL
    Default: ${DSSC_HOST}
    MinLength: 1
    MaxLength: 100
    ConstraintDescription: You must enter a Smartcheck host URL

  PreregistryUser:
    Type: String
    Description: The user for Pre-Registry
    Default: ${DSSC_REGUSER}
    MinLength: 1
    MaxLength: 100
    ConstraintDescription: You must enter a user for the Pre-Registry

  PreregistryPwd:
    Type: String
    Description: The password for Pre-Registry user
    Default: ${DSSC_REGPASSWORD}
    MinLength: 1
    MaxLength: 100
    ConstraintDescription: You must enter a password for the Pre-Registry user

  KubectlRoleName:
    Type: String
    Description: The Role for the deployments on EKS
    Default: ${AWS_PROJECT}EksClusterCodeBuildKubectlRole
    MinLength: 1
    MaxLength: 500
    ConstraintDescription: Do not change this

  EksClusterName:
    Type: String
    Description: The name of the EKS cluster
    Default: ${AWS_PROJECT}
    MinLength: 1
    MaxLength: 50
    ConstraintDescription: Do not change this

  AppSecKey:
    Type: String
    Description: The registration key for Cloud One Application Security
    Default: ${TREND_AP_KEY}
    MinLength: 1
    MaxLength: 50
    ConstraintDescription: Do not change this

  AppSecSecret:
    Type: String
    Description: The registration secret for Cloud One Application Security
    Default: ${TREND_AP_SECRET}
    MinLength: 1
    MaxLength: 50
    ConstraintDescription: Do not change this

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
      - Label:
          default: AWS
        Parameters:
          - CodeCommitRepoName
          - EcrRepoName
      - Label:
          default: DeepSecurity/Smartcheck
        Parameters:
          - SmartcheckHost
          - SmartcheckUser
          - SmartcheckPwd
          - PreregistryHost
          - PreregistryUser
          - PreregistryPwd
          - KubectlRoleName
          - EksClusterName
          - AppSecKey
          - AppSecSecret
    ParameterLabels:
      CodeCommitRepoName:
        default: CodeCommit Repositry Name (Project Name)
      EcrRepoName:
        default: ECR Repository Name
      SmartcheckHost:
        default: Smartcheck Host URL
      SmartcheckUser:
        default: Smartcheck User
      SmartcheckPwd:
        default: Smartcheck Password
      PreregistryHost:
        default: Pre-registry Host URL
      PreregistryUser:
        default: Pre-registry User
      PreregistryPwd:
        default: Pre-registry Password
      KubectlRoleName:
        default: Kubectl IAM role
      EksClusterName:
        default: EKS cluster name
      AppSecKey:
        default: Application Security Key
      AppSecSecret:
        default: Application Security Secret
Resources:
  EcrDockerRepository:
    Type: AWS::ECR::Repository
    Properties:
      RepositoryName: !Ref EcrRepoName
    DeletionPolicy: Retain

  CodePipelineArtifactBucket:
    Type: AWS::S3::Bucket
    DeletionPolicy: Retain

  CodePipelineServiceRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Principal:
              Service: codepipeline.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: codepipeline-access
          PolicyDocument:
            Version: 2012-10-17
            Statement:
              - Resource: !GetAtt CodeCommitRepo.Arn
                Effect: Allow
                Action:
                  - codecommit:GetBranch
                  - codecommit:GetCommit
                  - codecommit:UploadArchive
                  - codecommit:GetUploadArchiveStatus
                  - codecommit:CancelUploadArchive
              - Resource:
                  - !Sub arn:aws:codebuild:\${AWS::Region}:\${AWS::AccountId}:project/\${PreScanBuild${1}}
                Effect: Allow
                Action:
                  - codebuild:StartBuild
                  - codebuild:StopBuild
                  - codebuild:BatchGetProjects
                  - codebuild:BatchGetBuilds
                  - codebuild:ListBuildsForProject
              - Resource: !Sub arn:aws:s3:::\${CodePipelineArtifactBucket}/*
                Effect: Allow
                Action:
                  - s3:PutObject
                  - s3:GetObject
                  - s3:GetObjectVersion
                  - s3:GetBucketVersioning
    DependsOn: CodePipelineArtifactBucket

  CodeBuildServiceRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: codebuild-access
          PolicyDocument:
            Version: 2012-10-17
            Statement:
              - Resource: !Sub arn:aws:iam::\${AWS::AccountId}:role/\${KubectlRoleName}
                Effect: Allow
                Action:
                  - sts:AssumeRole
              - Resource: '*'
                Effect: Allow
                Action:
                  - eks:Describe*
              - Resource: '*'
                Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
              - Resource: !Sub arn:aws:s3:::\${CodePipelineArtifactBucket}/*
                Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                  - s3:GetObjectVersion
              - Resource: '*'
                Effect: Allow
                Action:
                  - ecr:GetAuthorizationToken
              - Resource: '*'
                Effect: Allow
                Action:
                  - ec2:CreateNetworkInterface
                  - ec2:DescribeDhcpOptions
                  - ec2:DescribeNetworkInterfaces
                  - ec2:DeleteNetworkInterface
                  - ec2:DescribeSubnets
                  - ec2:DescribeSecurityGroups
                  - ec2:DescribeVpcs
                  - ec2:CreateNetworkInterfacePermission
              - Resource: !Sub arn:aws:ecr:\${AWS::Region}:\${AWS::AccountId}:repository/\${EcrDockerRepository}
                Effect: Allow
                Action:
                  - ecr:GetDownloadUrlForLayer
                  - ecr:BatchGetImage
                  - ecr:BatchCheckLayerAvailability
                  - ecr:PutImage
                  - ecr:InitiateLayerUpload
                  - ecr:UploadLayerPart
                  - ecr:CompleteLayerUpload

  CodeCommitRepo:
    Type: AWS::CodeCommit::Repository
    Properties:
      RepositoryDescription: Code Repository for the DevSecOps sample
      RepositoryName: !Ref CodeCommitRepoName

  PreScanBuild${1}:
    Type: AWS::CodeBuild::Project
    Properties:
      Artifacts:
        Type: CODEPIPELINE
      Source:
        Type: CODEPIPELINE
        BuildSpec: buildspec.yml
      Environment:
        ComputeType: BUILD_GENERAL1_SMALL
        Type: LINUX_CONTAINER
        Image: aws/codebuild/docker:17.09.0
        EnvironmentVariables:
          - Name: PRE_SCAN_REPOSITORY
            Value: !Ref PreregistryHost
          - Name: PRE_SCAN_USER
            Value: !Ref PreregistryUser
          - Name: PRE_SCAN_PWD
            Value: !Ref PreregistryPwd
          - Name: SMARTCHECK_HOST
            Value: !Ref SmartcheckHost
          - Name: SMARTCHECK_USER
            Value: !Ref SmartcheckUser
          - Name: SMARTCHECK_PWD
            Value: !Ref SmartcheckPwd
          - Name: EKS_KUBECTL_ROLE_ARN
            Value: !Sub arn:aws:iam::\${AWS::AccountId}:role/\${KubectlRoleName}
          - Name: EKS_CLUSTER_NAME
            Value: !Sub ${AWS_PROJECT}
          - Name: REPOSITORY_URI
            Value: !Sub \${AWS::AccountId}.dkr.ecr.${AWS_REGION}.amazonaws.com/\${EcrDockerRepository}
          - Name: APPSEC_KEY
            Value: !Ref AppSecKey
          - Name: APPSEC_SECRET
            Value: !Ref AppSecSecret

      Name: PreScanBuild${1}
      Description: Pre-scan container image with Smartcheck and push to registry
      ServiceRole: !GetAtt CodeBuildServiceRole.Arn

  CodePipelineDevSecOps:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      RoleArn: !GetAtt CodePipelineServiceRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref CodePipelineArtifactBucket
      Stages:
        - Name: Source
          Actions:
            - Name: Sample-App
              ActionTypeId:
                Category: Source
                Owner: AWS
                Version: 1
                Provider: CodeCommit
              Configuration:
                RepositoryName: !GetAtt CodeCommitRepo.Name
                BranchName: master
              OutputArtifacts:
                - Name: Sample-App
              RunOrder: 1
        - Name: BuildAndScan
          Actions:
            - Name: BuildAndScan
              ActionTypeId:
                Category: Build
                Owner: AWS
                Version: 1
                Provider: CodeBuild
              Configuration:
                ProjectName: !Ref PreScanBuild${1}
              InputArtifacts:
                - Name: Sample-App
              OutputArtifacts:
                - Name: PreScanOutput
              RunOrder: 1
EOF

}

function create_eks_pipeline {
#$1 = name of the pipeline
#$1 = name of the pipeline (${AWS_PROJECT}${APP[$i]})
LOWER1=`echo ${1} | awk '{ print tolower($0) }'`

#check of pipeline exists
aws_pipeline_exists="false"
aws_pipelines=( `aws codepipeline list-pipelines --output json --region $AWS_REGION| jq -r '.pipelines[].name'` )
aws_pipeline=''
for i in "${!aws_pipelines[@]}"; do
  #printf "%s" "Pipeline $i =  ${aws_pipelines[$i]}.........."
  if [[ "${aws_pipelines[$i]}" =~ "${1}Pipeline" ]]; then
      aws_pipeline_exists="true"
      aws_pipeline=${aws_pipelines[$i]}
      break
  fi
done

#check if ECR repo exists
aws_ecr_repo_exists="false"
aws_ecr_repos=(`aws ecr describe-repositories --region ${AWS_REGION} | jq -r '.repositories[].repositoryName'`)
aws_ecr_repo=''
for i in "${!aws_ecr_repos[@]}"; do
  #printf "%s" "Repo $i =  ${aws_ecr_repos[$i]}"
  aws_ecr_repo=`echo ${1} | awk '{ print tolower($0) }'`
  if [[ "${aws_ecr_repos[$i]}" =~ "${1}" ]]; then
      #printf "%s\n" "Matching ECR repository found: ${aws_ecr_repo}"
      aws_ecr_repo_exists="true"
      break
  else
     aws_ecr_repo=''
  fi
done

#check if CodeCommit repo exists
aws_cc_repo_exists="false"
aws_cc_repos=(`aws codecommit list-repositories --region $AWS_REGION | jq -r '.repositories[].repositoryName'`)
aws_cc_repo=''
for i in "${!aws_cc_repos[@]}"; do
  #printf '%s\n' "Checking CC Repo $i =  ${aws_cc_repos[$i]} ..........Comparing with ${1}"
  if [[ "${aws_cc_repos[$i]}" =~ "${1}" ]]; then
      #printf "%s\n" "Found CodeCommit Repo "${aws_cc_repos[$i]}
      aws_cc_repo=${aws_cc_repos[$i]}
      export AWS_CC_REPO_URL=`aws codecommit get-repository --region $AWS_REGION --repository-name ${aws_cc_repo} | jq -r '.repositoryMetadata.cloneUrlHttp' | sed 's/https\:\/\///'`
      #printf "%s\n" "Found CodeCommit Repo URL ${AWS_CC_REPO_URL}"
      aws_cc_repo_exists="true"
      break
  else
    aws_cc_repo=''
  fi
done

#check if Cloudformation Stack exists.
aws_pipeline_stack_exists="false"
aws_pipeline_stack=""
aws_pipeline_stacks=(`aws cloudformation describe-stacks --output json --region $AWS_REGION| jq -r '.Stacks[].StackName'` )
for i in "${!aws_pipeline_stacks[@]}"; do
  # printf "%s\n" "stack $i =  ${aws_pipeline_stacks[$i]}"
  if [[ "${aws_pipeline_stacks[$i]}" =~ "${1}Pipeline" ]]; then
     aws_pipeline_stack_exists="true"
     aws_pipeline_stack=${aws_pipeline_stacks[$i]}
     aws_pipeline_stack_status=`aws cloudformation describe-stacks --stack-name ${aws_pipeline_stacks[$i]}  --output json --region $AWS_REGION| jq -r '.Stacks[].StackStatus'`
     #printf "%s\n" "Found stack ${aws_pipeline_stack} with status: ${aws_pipeline_stack_status}"
     break
  fi
done

#if pipeline exists and ECR repo exists, and , CodeCommit repo exists, and StackStatus is CREATE_COMPLETE, reuse them
toCreateNewEnvironment="true"
if [[ "${aws_pipeline_exists}" = "true" &&  "${aws_ecr_repo_exists}" = "true" &&  "${aws_cc_repo_exists}" = "true" && "${aws_pipeline_stack_status}" = "CREATE_COMPLETE" ]]; then
    printf "%s\n" "Reusing existing: CodeCommit repository ${aws_cc_repo}, ECR repository ${aws_ecr_repo}, Pipeline ${1} and Pipeline Cloudformation stack ${aws_pipeline_stack}"
    toCreateNewEnvironment="false"
else
  if [[ "${aws_pipeline_exists}" = "false" &&  "${aws_ecr_repo_exists}" = "false" &&  "${aws_cc_repo_exists}" = "false" && "${aws_pipeline_stack_exists}" = "false" ]]; then
    printf '%s\n'  "No environment found:"
    printf '%s\n'  "-------------------------------"
    printf '%s\n'  "   CodeCommit repo: ${aws_cc_repo} exists = ${aws_cc_repo_exists}"
    printf '%s\n'  "   CloudFormation stack: ${aws_pipeline_stack} status = ${aws_pipeline_stack_status}"
    printf '%s\n'  "   CodePipeline: ${aws_pipeline} exists = ${aws_pipeline_exists}"
    printf '%s\n'  "   ECR repo: ${aws_ecr_repo} exists = ${aws_ecr_repo_exists}"
    printf "%s\n" "creating: CodeCommit repository ${aws_cc_repo}, ECR repository ${aws_ecr_repo}, Pipeline ${1} and Cloudformation stack ${aws_pipeline_stack}"
    toCreateNewEnvironment="true"
  else
    #we have an inconsistent environement.
    #if old stack exists -> delete it
    printf '%s\n'  "Inconsistent environment found for ${1}:"
    printf '%s\n'  "-------------------------------------------------"
    printf '%s\n'  "   CodeCommit repo: ${aws_cc_repo} exists = ${aws_cc_repo_exists}"
    printf '%s\n'  "   CloudFormation stack: ${aws_pipeline_stack} status = ${aws_pipeline_stack_status}"
    printf '%s\n'  "   CodePipeline: ${aws_pipeline} exists = ${aws_pipeline_exists}"
    printf '%s\n'  "   ECR repo: ${aws_ecr_repo} exists = ${aws_ecr_repo_exists}"

    if [[ "${aws_pipeline_stack_exists}" = "true" ]]; then
      printf '%s \n' "Cleaning up old Cloudformation Stack: ${aws_pipeline_stack}"
      aws cloudformation delete-stack --stack-name ${aws_pipeline_stack} --region ${AWS_REGION}
      aws cloudformation wait stack-delete-complete --stack-name ${aws_pipeline_stack}  --region ${AWS_REGION}
    fi

    #if old pipeline exists -> delete it
    if [[ "${aws_pipeline_exists}" = "true" ]]; then
      printf "%s\n" "Cleaning up old pipeline ${aws_pipeline}Pipeline"
      aws codepipeline delete-pipeline --name ${aws_pipeline}
    fi

    #if old ecr repo exists -> delete it
    if [[ "${aws_ecr_repo_exists}" = "true" ]]; then
      aws_ecr_repo=`echo ${1} | awk '{ print tolower($0) }'`
      printf "%s\n" "Cleaning up old ECR repository: ${aws_ecr_repo}"
      DUMMY=`aws ecr delete-repository --repository-name ${aws_ecr_repo} --region ${AWS_REGION} --force`
    fi

    #if old cc repo exists -> delete it
    if [[ "${aws_cc_repo_exists}" = "true" ]]; then
      aws_cc_repo=`echo ${1} | awk '{ print tolower($0) }'`
      printf "%s\n" "Cleaning up old CodeCommit repository: ${aws_cc_repo}"
      DUMMY=`aws codecommit delete-repository --repository-name ${aws_cc_repo} --region ${AWS_REGION}`
    fi
    sleep 20  #make sure that stack is totally gone
  fi
fi


if [[ "${toCreateNewEnvironment}" = "true" ]]; then
#creating new pipeline/stack
  create_pipeline_yaml ${1}
  printf '%s\n' "Creating Cloudformation Stack and Pipeline ${1}"...
  DUMMY=`aws cloudformation create-stack --stack-name ${1}Pipeline --region ${AWS_REGION}  --template-body file://${1}Pipeline.yml  --capabilities CAPABILITY_IAM`
  printf '%s\n' "Waiting for Cloudformation stack ${1}Pipeline to be created. "
  DUMMY=`aws cloudformation wait stack-create-complete --stack-name ${1}Pipeline  --region ${AWS_REGION}`
fi
}  #end of function

ROLE="    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/${AWS_PROJECT}EksClusterCodeBuildKubectlRole\n      username: build\n      groups:\n        - system:masters"

kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml
patched=`kubectl get -n kube-system configmap/aws-auth -o yaml`
if [[ "${patched}" =~ "${AWS_PROJECT}EksClusterCodeBuildKubectlRole"   ]];then
    printf "%s\n" "aws-auth configmap already patched for ${AWS_PROJECT}"
  else
    printf "%s\n" "Patching aws-auth configmap for ${AWS_PROJECT}"
    kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
fi

create_eks_pipeline ${AWS_PROJECT}${APP1}
create_eks_pipeline ${AWS_PROJECT}${APP2}
create_eks_pipeline ${AWS_PROJECT}${APP3}
