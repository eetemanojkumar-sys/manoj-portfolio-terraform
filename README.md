# Manoj Kumar — Modular Terraform Portfolio Hosting

This repository provisions a **new** EC2/Nginx instance and a **new** S3 static website bucket in `ap-south-1`. EC2 reads site objects from S3 with an instance role. `deploy.sh` uploads files from `website/` to S3 and refreshes EC2 using Systems Manager.

## Modules
- `modules/ec2`: Ubuntu EC2, encrypted root disk, Nginx bootstrap
- `modules/s3`: S3 static website and public object-read policy
- `modules/iam`: least-privilege read access to the project bucket + SSM
- `modules/security`: public HTTP and optional SSH restricted to your CIDR
- Root module: connects the modules

## Safety and privacy
- Uses new resources only; does not import or modify previously existing portfolio resources.
- EC2 and bucket have `prevent_destroy = true`.
- The S3 website endpoint is public HTTP; only object reads are public. Do not put secrets in `website/`.
- The portfolio page links to `resume.pdf`. Include the resume only if you want its contact information publicly available.
- Never commit `terraform.tfvars`, state files, AWS credentials, or private SSH keys.
- EC2 and public IPv4 can incur charges. Check AWS pricing.

## Prerequisites
Install Terraform 1.6+, AWS CLI v2 and Python 3. Configure AWS CLI credentials or an SSO profile with required EC2, IAM, S3 and SSM permissions.

SSH is disabled by default. If needed, create a key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/manoj_portfolio
```
Then set `enable_ssh = true`, use only the public-key file path, and configure `ssh_allowed_cidr` to your trusted public IP as `x.x.x.x/32`.

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

Your local AWS identity uploads the website to S3 and invokes SSM. EC2 uses its instance role to read the project bucket; no long-lived AWS keys are stored on EC2.

## Verify
```bash
terraform output -raw s3_website_endpoint
terraform output -raw ec2_url
```
The S3 static website endpoint is HTTP-only. Use CloudFront + HTTPS for production/custom-domain access.

## Cleanup
Deletion is blocked by `prevent_destroy`. If you later decide to remove these new resources, back up state, deliberately remove safeguards, and review the plan carefully before applying.
