#!/usr/bin/env bash
# Deletes everything deploy.sh created: the instance (and its disk), the security group,
# the instance profile and the IAM role. Stops all charges. Cannot be undone.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ID=$(cat "$DIR/.instance-id"); REGION=$(cat "$DIR/.region")

read -r -p "Terminate $ID in $REGION and delete its role and security group? Type 'delete' to confirm: " OK
[ "$OK" = "delete" ] || { echo "Cancelled."; exit 1; }

aws ec2 terminate-instances --region "$REGION" --instance-ids "$ID" >/dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$ID"
echo "Instance terminated."

SG=$(aws ec2 describe-security-groups --region "$REGION" --filters Name=group-name,Values=bouncer-no-inbound \
  --query 'SecurityGroups[0].GroupId' --output text)
[ "$SG" = "None" ] || aws ec2 delete-security-group --region "$REGION" --group-id "$SG"

aws iam remove-role-from-instance-profile --instance-profile-name bouncer-ssm-profile --role-name bouncer-ssm-role 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name bouncer-ssm-profile 2>/dev/null || true
aws iam detach-role-policy --role-name bouncer-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role --role-name bouncer-ssm-role 2>/dev/null || true

rm -f "$DIR/.instance-id" "$DIR/.region"
echo "All Bouncer AWS resources deleted."
