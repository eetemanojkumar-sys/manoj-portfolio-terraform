
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate Tools') {
            steps {
                sh '''
                    set -eu

                    echo "Checking required tools..."

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

                    echo "All required tools and files are available."
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
            steps {
                sh '''
                    set -eu

                    terraform plan \
                        -input=false \
                        -out=tfplan
                '''
            }
        }

        stage('Apply Infrastructure') {
            steps {
                sh '''
                    set -eu

                    terraform apply \
                        -input=false \
                        -auto-approve \
                        tfplan

                    echo "Terraform apply completed."

                    terraform output
                '''
            }
        }

        stage('Deploy Portfolio') {
            steps {
                sh '''
                    set -eu

                    echo "Checking deployment script syntax..."
                    bash -n deploy.sh

                    echo "Starting portfolio deployment..."
                    bash ./deploy.sh
                '''
            }
        }

        stage('Verify Website') {
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
    }

    post {
        success {
            echo 'SUCCESS: Portfolio pipeline completed successfully.'
        }

        failure {
            echo 'FAILED: Check the first failed stage in the Jenkins console output.'
        }

        always {
            sh '''
                rm -f tfplan
            '''
            echo 'Jenkins pipeline finished.'
        }
    }
}
