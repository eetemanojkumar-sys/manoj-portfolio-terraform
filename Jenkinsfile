pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    parameters {
        booleanParam(
            name: 'DESTROY_INFRASTRUCTURE',
            defaultValue: false,
            description: 'Check only when you intentionally want Terraform to destroy the portfolio infrastructure.'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Validate Tools') {
            steps {
                sh '''
                    set -eu
                    git --version
                    terraform --version
                    aws --version
                    python3 --version
                    curl --version
                    test -f website/index.html
                    test -f deploy.sh
                    test -f main.tf
                    test -f Jenkinsfile
                    chmod +x deploy.sh
                '''
            }
        }

        stage('Terraform Format & Validate') {
            steps {
                sh '''
                    set -eu
                    terraform fmt -check -recursive
                    terraform init -input=false
                    terraform validate
                '''
            }
        }

        stage('Plan Infrastructure') {
            when { expression { !params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    terraform plan -input=false -out=tfplan
                '''
            }
        }

        stage('Apply Infrastructure') {
            when { expression { !params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    terraform apply -input=false -auto-approve tfplan
                    terraform output
                '''
            }
        }

        stage('Deploy Portfolio') {
            when { expression { !params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    bash -n deploy.sh
                    bash ./deploy.sh
                '''
            }
        }

        stage('Verify Website') {
            when { expression { !params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    WEBSITE_URL="$(terraform output -raw ec2_url)"
                    echo "Testing website: ${WEBSITE_URL}"
                    STATUS="$(curl -sS -L \
                        --connect-timeout 10 \
                        --max-time 30 \
                        --retry 5 \
                        --retry-delay 3 \
                        --retry-connrefused \
                        -o /tmp/portfolio-response.html \
                        -w "%{http_code}" \
                        "${WEBSITE_URL}/")"
                    echo "HTTP Status: ${STATUS}"
                    if [ "${STATUS}" != "200" ]; then
                        echo "ERROR: Website verification failed."
                        cat /tmp/portfolio-response.html
                        exit 1
                    fi
                    echo "SUCCESS: Portfolio website is accessible."
                '''
            }
        }

        stage('Backup Terraform State to S3') {
            when { expression { params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    umask 077

                    echo "Checking that Terraform state exists..."
                    terraform state list

                    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
                    REGION="ap-south-1"
                    BACKUP_BUCKET="manoj-portfolio-tfstate-backup-${ACCOUNT_ID}-${REGION}"

                    echo "Using dedicated private backup bucket: ${BACKUP_BUCKET}"
                    echo "The public website bucket will not be used for state backups."

                    if ! aws s3api head-bucket --bucket "${BACKUP_BUCKET}" >/dev/null 2>&1; then
                        echo "Creating private state-backup bucket..."
                        aws s3api create-bucket \
                            --bucket "${BACKUP_BUCKET}" \
                            --region "${REGION}" \
                            --create-bucket-configuration LocationConstraint="${REGION}"
                    fi

                    aws s3api put-public-access-block \
                        --bucket "${BACKUP_BUCKET}" \
                        --public-access-block-configuration \
                        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

                    aws s3api put-bucket-versioning \
                        --bucket "${BACKUP_BUCKET}" \
                        --versioning-configuration Status=Enabled

                    aws s3api put-bucket-encryption \
                        --bucket "${BACKUP_BUCKET}" \
                        --server-side-encryption-configuration \
                        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

                    STATE_FILE="$(mktemp)"
                    VERIFY_FILE="$(mktemp)"
                    trap 'rm -f "${STATE_FILE}" "${VERIFY_FILE}"' EXIT

                    echo "Exporting Terraform state without printing its contents..."
                    terraform state pull > "${STATE_FILE}"

                    python3 - "${STATE_FILE}" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    state = json.load(f)
if not isinstance(state, dict) or not state.get("version"):
    raise SystemExit("ERROR: Terraform state JSON is invalid.")
if not state.get("resources"):
    raise SystemExit("ERROR: Terraform state contains no managed resources; refusing to destroy.")
print("Terraform state JSON is valid and contains managed resources.")
PY

                    TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
                    BACKUP_KEY="portfolio/terraform-state-${BUILD_NUMBER:-manual}-${TIMESTAMP}.json"
                    BACKUP_URI="s3://${BACKUP_BUCKET}/${BACKUP_KEY}"

                    echo "Uploading state backup to ${BACKUP_URI}"
                    aws s3 cp "${STATE_FILE}" "${BACKUP_URI}" --region "${REGION}" --sse AES256

                    echo "Verifying uploaded backup..."
                    aws s3api head-object \
                        --bucket "${BACKUP_BUCKET}" \
                        --key "${BACKUP_KEY}" \
                        --region "${REGION}" >/dev/null

                    aws s3 cp "${BACKUP_URI}" "${VERIFY_FILE}" --region "${REGION}" >/dev/null
                    if ! cmp -s "${STATE_FILE}" "${VERIFY_FILE}"; then
                        echo "ERROR: Downloaded backup does not match Terraform state."
                        exit 1
                    fi

                    echo "Verified Terraform state backup: ${BACKUP_URI}"
                    echo "Only a successful, verified backup allows the destroy plan stage to run."
                '''
            }
        }

        stage('Plan Terraform Destroy') {
            when { expression { params.DESTROY_INFRASTRUCTURE } }
            steps {
                sh '''
                    set -eu
                    echo "Creating destroy plan after verified S3 state backup..."
                    terraform plan -destroy -input=false -out=tf-destroy-plan
                    terraform show tf-destroy-plan
                '''
            }
        }

        stage('Terraform Destroy') {
            when { expression { params.DESTROY_INFRASTRUCTURE } }
            steps {
                input(
                    message: 'The Terraform state backup has been uploaded to S3 and verified. Confirm applying the destroy plan. This may take the portfolio offline.',
                    ok: 'Destroy Resources'
                )
                sh '''
                    set -eu
                    test -f tf-destroy-plan
                    terraform apply -input=false -auto-approve tf-destroy-plan
                    echo "Terraform destroy completed."
                '''
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Jenkins pipeline completed successfully.'
        }
        failure {
            echo 'FAILED: Check the first failed stage. If the state backup fails, the destroy stage cannot run.'
        }
        always {
            sh 'rm -f tfplan tf-destroy-plan'
            echo 'Jenkins pipeline finished.'
        }
    }
}
