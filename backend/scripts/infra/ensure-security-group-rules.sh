#!/usr/bin/env bash
# Ensures the shared supporting-services security group has ingress rules
# for every port the API/worker/admin services need to reach on the
# EC2 box running Postgres/Redis/Kafka/Elasticsearch/MinIO.
#
# Why this exists: on the 2026-08-24 Mumbai deployment, Redis (56379) and
# MinIO (59000) were opened by hand early on, but Elasticsearch (59200)
# and Kafka (59092) were simply forgotten — nobody had a single list to
# check against. That silently broke /search/profiles for hours before
# being traced to missing ingress rules. This script is the checklist,
# made runnable and idempotent (authorize-security-group-ingress is safe
# to re-run; AWS returns InvalidPermission.Duplicate if the rule already
# exists, which this script treats as success).
#
# Usage: SG_ID=sg-xxxx VPC_CIDR=172.31.0.0/16 ./ensure-security-group-rules.sh

set -euo pipefail

SG_ID="${SG_ID:?Set SG_ID to the supporting-services security group id, e.g. sg-058208ed4c5f06c64}"
VPC_CIDR="${VPC_CIDR:?Set VPC_CIDR to the VPC CIDR, e.g. 172.31.0.0/16}"
REGION="${AWS_REGION:-ap-south-1}"

# port:description
PORTS=(
  "56379:Redis"
  "59000:MinIO"
  "59200:Elasticsearch"
  "59092:Kafka"
)

for entry in "${PORTS[@]}"; do
  port="${entry%%:*}"
  name="${entry##*:}"
  echo "Ensuring ingress for ${name} (tcp/${port}) from ${VPC_CIDR} on ${SG_ID}..."
  if aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port "$port" \
    --cidr "$VPC_CIDR" \
    --region "$REGION" >/dev/null 2>&1; then
    echo "  -> rule created"
  else
    echo "  -> already present (or authorize call returned non-zero; verify manually if unexpected)"
  fi
done

echo "Done. Current ingress rules:"
aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpRanges[0].CidrIp]' \
  --output table
