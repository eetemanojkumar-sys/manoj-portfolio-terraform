#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="${ROOT_DIR}/website"

command -v terraform >/dev/null || { echo "Terraform is required." >&2; exit 1; }
command -v aws >/dev/null || { echo "AWS CLI is required." >&2; exit 1; }
[[ -f "${WEBSITE_DIR}/index.html" ]] || { echo "Missing website/index.html" >&2; exit 1; }

BUCKET="$(terraform -chdir="${ROOT_DIR}" output -raw s3_bucket_name)"
INSTANCE_ID="$(terraform -chdir="${ROOT_DIR}" output -raw ec2_instance_id)"
REGION="$(terraform -chdir="${ROOT_DIR}" output -raw aws_region 2>/dev/null || true)"
REGION="${REGION:-ap-south-1}"

echo "Uploading website/ to s3://${BUCKET}/ ..."
aws s3 sync "${WEBSITE_DIR}/" "s3://${BUCKET}/" --delete --region "${REGION}"

COMMAND_ID="$(aws ssm send-command \
  --region "${REGION}" \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --comment "Refresh portfolio website from S3" \
  --parameters "$(python3 -c 'import json,sys; print(json.dumps({"commands":[
"set -e",
"aws s3 sync s3://'"${BUCKET}"'/ /var/www/html/ --delete --region '"${REGION}"'",
"chown -R www-data:www-data /var/www/html",
"find /var/www/html -type d -exec chmod 755 {} +",
"find /var/www/html -type f -exec chmod 644 {} +",
"nginx -t",
"systemctl reload nginx"
]}))')" \
  --query 'Command.CommandId' --output text)"

echo "SSM command submitted: ${COMMAND_ID}"
echo "Waiting for deployment result..."
for attempt in $(seq 1 30); do
  STATUS="$(aws ssm get-command-invocation --region "${REGION}" \
    --command-id "${COMMAND_ID}" --instance-id "${INSTANCE_ID}" \
    --query 'Status' --output text 2>/dev/null || true)"
  case "${STATUS}" in
    Success)
      echo "Deployment succeeded."
      echo "EC2: $(terraform -chdir="${ROOT_DIR}" output -raw ec2_url)"
      echo "S3:  $(terraform -chdir="${ROOT_DIR}" output -raw s3_website_endpoint)"
      exit 0
      ;;
    Failed|Cancelled|TimedOut|Undeliverable|Terminated)
      aws ssm get-command-invocation --region "${REGION}" \
        --command-id "${COMMAND_ID}" --instance-id "${INSTANCE_ID}" \
        --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' \
        --output json || true
      echo "Deployment failed with status: ${STATUS}" >&2
      exit 1
      ;;
  esac
  sleep 5
done

echo "Command is still running or instance is not yet online. Check Systems Manager Run Command; rerun this script after the instance registers." >&2
exit 2
