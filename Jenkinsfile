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
            when {
                expression { !params.DESTROY_INFRASTRUCTURE }
            }
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
            when {
                expression { !params.DESTROY_INFRASTRUCTURE }
            }
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
            when {
                expression { !params.DESTROY_INFRASTRUCTURE }
            }
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
            when {
                expression { !params.DESTROY_INFRASTRUCTURE }
            }
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

        stage('Confirm Terraform Destroy') {
            when {
                expression { params.DESTROY_INFRASTRUCTURE }
            }
            steps {
                input(
                    message: 'This will run terraform destroy against the state in this Jenkins workspace. Confirm that you intend to remove the resources managed by that state.',
                    ok: 'Confirm Destroy'
                )
                sh '''
                    set -eu
                    echo "Generating destroy plan for review..."
                    terraform plan -destroy -input=false -out=tf-destroy-plan
                    echo "Destroy plan saved as tf-destroy-plan."
                    terraform show tf-destroy-plan
                '''
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.DESTROY_INFRASTRUCTURE }
            }
            steps {
                input(
                    message: 'Final confirmation: apply the destroy plan shown in the previous stage? This may take your portfolio offline.',
                    ok: 'Destroy Resources'
                )
                sh '''
                    set -eu
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
            echo 'FAILED: Check the first failed stage in the Jenkins console output.'
        }

        always {
            sh '''
                rm -f tfplan tf-destroy-plan
            '''
            echo 'Jenkins pipeline finished.'
        }
    }
}
