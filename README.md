# Modular Terraform Portfolio Hosting (AWS)

This repository provisions a **new** EC2/Nginx instance and a **new** S3 static website bucket in `ap-south-1`. EC2 reads site objects from S3 with an instance role. `deploy.sh` uploads files from `website/` to S3 and refreshes EC2 using Systems Manager.

## Modules
- `modules/ec2`: Ubuntu EC2, encrypted root disk, Nginx bootstrap
- `modules/s3`: S3 static website and object-read policy
- `modules/iam`: least-privilege read access to the project bucket + SSM
- `modules/security`: public HTTP and optional SSH restricted to your CIDR
- Root module: connects resources

## Safety / privacy
- Uses new resources only; does not import or modify the previously existing portfolio EC2 or bucket.
- EC2 and bucket have `prevent_destroy = true`.
- The S3 endpoint is public HTTP, and only object reads are granted publicly. Do not put secrets in `website/`.
- The portfolio links to `resume.pdf`. A resume can contain public contact information; only commit it if you want it accessible from the public website.
- Never commit `terraform.tfvars`, state files, credentials, or private SSH keys.
- EC2 and public IPv4 may incur charges. Check AWS pricing.

## Prerequisites
Terraform 1.6+, AWS CLI v2, Python 3, and an AWS CLI profile/credentials with required EC2, IAM, S3 and SSM permissions.

Optional SSH key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/manoj_portfolio
``
Use only the `*.pub` file in Terraform and restrict SSH to your current public IPv4 `/32`. For SSM-only, set `enable_ssh = false`.

## Provision
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: trusted public IP CIDR and public_key_path
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
# Review the plan. It should create only this project's new resources.
terraform apply tfplan
```

## Deploy the same site to S3 and EC2
Place your actual portfolio page at `website/index.html`. If it includes `href="resume.pdf"`, put the approved resume at `website/resume.pdf`.

```bash
chmod +x deploy.sh
./deploy.sh
```

The local AWS identity uploads files to S3 and invokes SSM. The EC2 instance role is read-only to the new bucket; no long-lived AWS keys are stored on EC2.

## Verify
```bash
terraform output -raw s3_website_endpoint
terraform output -raw ec2_url
```
S3's static website endpoint is HTTP only. Use CloudFront + HTTPS for production/custom-domain access.

## Cleanup
Deletion is intentionally blocked by `prevent_destroy`. If you later decide to remove these newly created resources, back up state, deliberately remove safeguards, and carefully review the plan before applying.
