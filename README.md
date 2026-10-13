# Manoj Kumar — Modular Terraform Portfolio Hosting

This repository provisions a **new** EC2/Nginx instance and a **new** S3 static website bucket in the configured AWS region (default `ap-south-1`). EC2 reads website objects from S3 using an instance role. Website deployment and remote refresh use AWS Systems Manager (SSM), so you do not need to SSH or interactively log in to the target web server.

## Modules
- `modules/ec2`: Ubuntu EC2, encrypted root disk, cloud-init bootstrap for Nginx and SSM Agent
- `modules/s3`: S3 static website and public object-read policy
- `modules/iam`: least-privilege read access to the project bucket + `AmazonSSMManagedInstanceCore`
- `modules/security`: public HTTP and optional SSH restricted to your CIDR
- Root module: connects the modules

## Bootstrap and remote management
At first boot, EC2 user data writes diagnostics to `/var/log/portfolio-bootstrap.log`, installs Nginx, installs/starts the SSM Agent, and attempts to sync the website from S3. The deployment script waits for the instance to show as **SSM Online**, uploads `website/` to S3, then refreshes Nginx content with SSM Run Command.

For SSM to work, the instance must have:
- The Terraform-created instance profile with `AmazonSSMManagedInstanceCore`
- Outbound HTTPS (TCP 443) connectivity to AWS SSM endpoints and S3 (the configured security group permits outbound traffic)
- A supported SSM Agent installation and a valid AWS region

The local AWS identity running `deploy.sh` also needs permission to upload to this project's S3 bucket and use SSM describe/send/get-command APIs.

## Safety and privacy
- Uses new resources only; does not import or modify previously existing portfolio resources.
- EC2 and bucket have `prevent_destroy = true`; Terraform will block ordinary destroy plans until that safeguard is deliberately changed.
- The S3 website endpoint is public HTTP; only object reads are public. Do not put secrets in `website/`.
- The portfolio page links to `resume.pdf`. Include the PDF only if you're comfortable making its contact information publicly available.
- Never commit `terraform.tfvars`, state files, AWS credentials, or private SSH keys.
- EC2 and public IPv4 can incur charges. Check AWS pricing.

## Prerequisites
Install Terraform 1.6+, AWS CLI v2 and Python 3. Configure AWS CLI credentials or an SSO profile with required EC2, IAM, S3 and SSM permissions.

SSH is disabled by default. If needed, create a key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/manoj_portfolio
```
Then set `enable_ssh = true`, use only the public-key file path, and configure `ssh_allowed_cidr` to your trusted public IP as `x.x.x.x/32`. SSH is optional; SSM is the intended management path.

## Provision
```bash
cp terraform.tfvars.example terraform.tfvars
# Review terraform.tfvars and set real values if enabling SSH.
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
# Review the plan; it must create only new resources for this project.
terraform apply tfplan
```

## Deploy the same portfolio to both endpoints
Put the supplied HTML at `website/index.html`. Since the page links to `resume.pdf`, add the PDF at `website/resume.pdf` only if you're comfortable making it public.

```bash
chmod +x deploy.sh
./deploy.sh
```

The script checks that the EC2 instance is **SSM Online** before uploading and issuing the remote refresh command. EC2 uses its instance role to read the project bucket; no long-lived AWS keys are stored on EC2.

## Verify
```bash
terraform output -raw s3_website_endpoint
terraform output -raw ec2_url
aws ssm describe-instance-information --region ap-south-1
```

The S3 static website endpoint is HTTP-only. Use CloudFront + HTTPS for production/custom-domain access.

## Cleanup
Deletion is blocked by `prevent_destroy` on the EC2 instance and bucket. If you later decide to remove these new resources, first back up the state, deliberately remove safeguards, and review the plan carefully. Never destroy the manually created master server as part of this project's cleanup.
