
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Portfolio Deployment: S3 + EC2 + Nginx + SSM
# ==========================================

echo "=========================================="
echo "Starting Portfolio Deployment"
echo "=========================================="

# Read values from Terraform outputs
BUCKET="$(terraform output -raw s3_bucket_name)"
INSTANCE_ID="$(terraform output -raw ec2_instance_id)"
REGION="$(terraform output -raw aws_region)"
WEBSITE_DIR="website"

# Validate required values
if [[ -z "${BUCKET}" || -z "${INSTANCE_ID}" || -z "${REGION}" ]]; then
  echo "ERROR: Missing required Terraform outputs."
  exit 1
fi

if [[ ! -d "${WEBSITE_DIR}" ]]; then
  echo "ERROR: Website directory '${WEBSITE_DIR}' not found."
  exit 1
fi

if [[ ! -f "${WEBSITE_DIR}/index.html" ]]; then
  echo "ERROR: ${WEBSITE_DIR}/index.html not found."
  exit 1
fi

echo "S3 bucket:   ${BUCKET}"
echo "EC2 instance: ${INSTANCE_ID}"
echo "AWS region:  ${REGION}"

# ==========================================
# Wait for EC2 to register with SSM
# ==========================================

echo "Waiting for EC2 instance to become available in SSM..."

SSM_READY="false"

for attempt in $(seq 1 30); do
  STATUS="$(aws ssm describe-instance-information \
    --region "${REGION}" \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || true)"

  if [[ "${STATUS}" == "Online" ]]; then
    SSM_READY="true"
    break
  fi

  echo "SSM status: ${STATUS}. Attempt ${attempt}/30"
  sleep 10
done

if [[ "${SSM_READY}" != "true" ]]; then
  echo "ERROR: EC2 instance did not become online in SSM."
  echo "Check the instance IAM role, SSM Agent, and network connectivity."
  exit 1
fi

echo "EC2 instance is online in SSM."

# ==========================================
# Upload website files to S3
# ==========================================

echo "Uploading ${WEBSITE_DIR}/ to s3://${BUCKET}/ ..."

aws s3 sync "${WEBSITE_DIR}/" "s3://${BUCKET}/" \
  --delete \
  --region "${REGION}"

echo "Website uploaded to S3 successfully."

# ==========================================
# Build the remote deployment command
# ==========================================

REMOTE_SCRIPT="$(cat <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

echo "Checking AWS CLI installation..."

if ! command -v aws >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y curl unzip

  curl -fsSL \
    https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
    -o /tmp/awscliv2.zip

  unzip -qo /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install

  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

aws --version

echo "Downloading portfolio files from S3..."
mkdir -p /var/www/html

aws s3 sync "s3://${BUCKET}/" /var/www/html/ \
  --delete \
  --region "${REGION}"

echo "Setting file ownership and permissions..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} +
find /var/www/html -type f -exec chmod 644 {} +

echo "Checking Nginx configuration..."
nginx -t

echo "Reloading Nginx..."
systemctl reload nginx

echo "Remote deployment completed."
EOF
)"

# Encode the entire remote script as one SSM command.
# This keeps installation and deployment in the same shell.
PARAMS="$(python3 -c '
import json, sys
print(json.dumps({"commands": [sys.stdin.read()]}))
' <<< "${REMOTE_SCRIPT}")"

# ==========================================
# Execute the deployment through SSM
# ==========================================

echo "Sending deployment command to EC2..."

COMMAND_ID="$(aws ssm send-command \
  --region "${REGION}" \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --comment "Deploy portfolio from S3 to Nginx" \
  --parameters "${PARAMS}" \
  --query 'Command.CommandId' \
  --output text)"

echo "SSM Command ID: ${COMMAND_ID}"

# ==========================================
# Wait for the SSM command to finish
# ==========================================

echo "Waiting for deployment to finish..."

if ! aws ssm wait command-executed \
  --region "${REGION}" \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}"; then

  echo "WARNING: SSM waiter reported that the command did not complete successfully."
fi

# Retrieve the final status
INVOCATION="$(aws ssm get-command-invocation \
  --region "${REGION}" \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --output json)"

STATUS="$(python3 -c '
import json, sys
print(json.load(sys.stdin).get("Status", "Unknown"))
' <<< "${INVOCATION}")"

echo "Deployment status: ${STATUS}"

if [[ "${STATUS}" != "Success" ]]; then
  echo "ERROR: Remote deployment failed."

  python3 -c '
import json, sys
data = json.load(sys.stdin)
print("Standard output:")
print(data.get("StandardOutputContent", ""))
print("Standard error:")
print(data.get("StandardErrorContent", ""))
' <<< "${INVOCATION}"

  exit 1
fi

# ==========================================
# Verify the website endpoint
# ==========================================

URL="$(terraform output -raw ec2_url 2>/dev/null || true)"

if [[ -n "${URL}" ]]; then
  echo "Checking website: ${URL}"

  if curl --fail --silent --show-error \
    --retry 5 --retry-delay 3 --retry-connrefused \
    --output /dev/null "${URL}"; then
    echo "Website HTTP check passed."
  else
    echo "WARNING: Deployment succeeded, but the HTTP check failed."
    echo "Check the EC2 security group, Nginx, and the website URL."
    exit 1
  fi
fi

echo "=========================================="
echo "Portfolio Deployment Completed Successfully"
echo "=========================================="
