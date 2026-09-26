#!/usr/bin/env bash
# Creates the Bouncer EC2 instance. No inbound ports, no SSH key: access is only via
# AWS Systems Manager (see connect.sh). Safe to re-run: it reuses the role and security group.
#
#   AWS_REGION=ap-south-1 INSTANCE_TYPE=m7i-flex.large ./deploy/aws/deploy.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
TYPE="${INSTANCE_TYPE:-m7i-flex.large}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROLE=bouncer-ssm-role
PROFILE=bouncer-ssm-profile
SG_NAME=bouncer-no-inbound

aws sts get-caller-identity --query Arn --output text

if [ -f "$DIR/.instance-id" ]; then
  echo "An instance already exists: $(cat "$DIR/.instance-id"). Run teardown.sh first if you want a new one."
  exit 1
fi

# IAM role so the instance can talk to Systems Manager (no SSH needed)
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
fi
if ! aws iam get-instance-profile --instance-profile-name "$PROFILE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$PROFILE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
  echo "Waiting for the instance profile to propagate…"; sleep 15
fi

VPC=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
[ "$VPC" != "None" ] || { echo "No default VPC in $REGION."; exit 1; }

# Security group with NO inbound rules (outbound stays open for apt, npm, Docker Hub and the model API)
SG=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG" = "None" ]; then
  SG=$(aws ec2 create-security-group --region "$REGION" --vpc-id "$VPC" --group-name "$SG_NAME" \
    --description "Bouncer: no inbound access, SSM only" --query GroupId --output text)
fi

AMI=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id --query Parameter.Value --output text)

ID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --instance-type "$TYPE" \
  --iam-instance-profile Name="$PROFILE" --security-group-ids "$SG" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3","Encrypted":true}}]' \
  --user-data "file://$DIR/user-data.sh" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bouncer},{Key=project,Value=bouncer-hackathon}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "$ID" > "$DIR/.instance-id"
echo "$REGION" > "$DIR/.region"
echo "Launched $ID ($TYPE, $REGION). Waiting for it to run…"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$ID"
echo "Running. First-boot setup takes about 5–8 minutes. Check with: ./deploy/aws/status.sh"
