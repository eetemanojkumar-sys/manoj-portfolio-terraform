
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/eetemanojkumar-sys/manoj-portfolio-terraform.git'
            }
        }

        stage('Validate Tools') {
            steps {
                sh '''
                    set -e
                    git --version
                    terraform --version
                    aws --version
                    python3 --version

                    test -f website/index.html
                    test -f deploy.sh
                    chmod +x deploy.sh
                '''
            }
        }

        stage('Terraform Format & Validate') {
            steps {
                sh '''
                    set -e
                    terraform fmt -check -recursive
                    terraform init -backend=false
                    terraform validate
                '''
            }
        }

        stage('Deploy Portfolio') {
            steps {
                sh '''
                    set -e
                    ./deploy.sh
                '''
            }
        }

        stage('Verify Website') {
            steps {
                sh '''
                    set -e

                    WEBSITE_URL="$(terraform output -raw ec2_url)"
                    echo "Testing: ${WEBSITE_URL}"

                    STATUS=$(curl -sS -L \
                        --connect-timeout 10 \
                        --max-time 30 \
                        -o /tmp/portfolio-response.html \
                        -w "%{http_code}" \
                        "${WEBSITE_URL}/")

                    echo "HTTP status: ${STATUS}"

                    test "${STATUS}" = "200"
                    grep -qi '<html' /tmp/portfolio-response.html

                    echo "Portfolio deployment and HTTP verification passed."
                '''
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Portfolio deployed and verified.'
        }

        failure {
            echo 'FAILED: Review the stage logs and fix the reported error.'
        }

        always {
            echo 'Jenkins pipeline finished.'
        }
    }
}
