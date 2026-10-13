# Modular Terraform Portfolio Hosting (AWS)

This project provisions a **new** EC2 instance and a **new** S3 bucket in `ap-south-1`, serves the same static portfolio from both, and lets EC2 read website objects from S3 using an instance role (no AWS access keys on EC2).

## Architecture

- Local `website/` directory is uploaded to S3 by `deploy.sh`.
- S3 static website hosting serves the files directly.
- EC2 runs Nginx. It uses its IAM instance profile to pull files from the S3 bucket.
- AWS Systems Manager (SSM) runs the refresh command remotely, so SSH is not required for deployment. SSH is still optionally enabled for troubleshooting, restricted to the CIDR you set.
- The S3 website endpoint is HTTP-only. For HTTPS/custom domain, add CloudFront and a certificate later.

## Safety and cost notes

- This project creates **new resources only**; it does not import, modify, or delete your existing EC2 instance or existing portfolio bucket.
- The bucket name includes a random suffix to avoid collision with existing buckets.
- `prevent_destroy = true` is enabled on the new bucket and EC2 instance. Terraform destroy will be blocked until you intentionally remove that safeguard.
- S3 static website hosting requires public object reads. The bucket policy grants anonymous `s3:GetObject` only; no public upload/list permission is granted. Do not put secrets or private files in `website/`.
- EC2 is billed while running; S3 storage/requests and public IPv4 may incur charges. Check current AWS pricing.
- The default website is a starter page. Replace `website/` with your portfolio files before deploying.
- Do not commit `terraform.tfstate`, `.tfvars`, private keys, or credentials.

## Prerequisites

1. AWS CLI v2 installed and configured locally (`aws configure` or an AWS SSO profile).
2. Terraform 1.6+ installed.
3. An AWS identity with permissions to create VPC security groups, EC2, IAM roles/profiles, S3 bucket/policy/website configuration, and SSM-related resources.
4. An EC2 key pair public key file if you want SSH access. Generate one if needed:
   `ssh-keygen -t ed25519 -f ~/.ssh/manoj_portfolio`
   Use `~/.ssh/manoj_portfolio.pub` as the public key path. Keep the private key safe. SSH is optional; SSM is used for deployment.
5. AWS account has Systems Manager access (outbound HTTPS from the instance is needed; default VPC internet connectivity generally provides it).

## Configure

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- `aws_region`: default `ap-south-1`
- `ssh_allowed_cidr`: your current public IP in CIDR form, e.g. `203.0.113.10/32` (replace with your real IP). Avoid `0.0.0.0/0`.
- `public_key_path`: path to your SSH public key. If you do not want SSH access, set `enable_ssh = false`; the key path is then not needed.
- `project_name`: short lowercase name.

Use a backend with remote state and locking for team/production use. This starter uses local state; back it up and never commit it.

## Provision

Run from this directory:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan carefully. It should show new resources with names similar to `manoj-portfolio-...`; it should not show changes to your existing resources.

Outputs:

```bash
terraform output
terraform output -raw s3_website_endpoint
terraform output -raw ec2_public_ip
terraform output -raw s3_bucket_name
terraform output -raw ec2_instance_id
```

## Deploy the same files to both hosts

Put your portfolio files in `website/`. The root `website/index.html` must exist.

```bash
chmod +x deploy.sh
./deploy.sh
```

The script:
1. Uploads `website/` to the new bucket.
2. Sends an SSM command to the new EC2 instance.
3. EC2 downloads the current S3 objects using its instance role and refreshes Nginx.

The machine running the script needs AWS credentials and permissions for `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `ssm:SendCommand`, and `ssm:GetCommandInvocation` for the relevant resources. The deployment script intentionally does not use SSH private keys.

If the first deployment fails because the instance has not registered with SSM yet, wait 2–5 minutes and run `./deploy.sh` again. Check Systems Manager > Fleet Manager / Managed nodes and the instance's IAM role if it keeps failing.

## Verify

- S3 site: open `terraform output -raw s3_website_endpoint`
- EC2 site: open `http://$(terraform output -raw ec2_public_ip)`
- SSM status: AWS Console > Systems Manager > Run Command, or inspect command output from the script.

## Troubleshooting

- **SSM target not online**: check the instance profile, outbound HTTPS/route/NAT, and SSM Agent status. Ubuntu AMIs usually include SSM Agent; user data attempts to enable/start it.
- **S3 AccessDenied on EC2**: check the instance profile attachment and the bucket ARN policy. The EC2 role is read-only.
- **S3 site AccessDenied**: verify the bucket policy and public access block settings. S3 static website endpoints require public access for this design.
- **Nginx default page**: inspect `/var/log/cloud-init-output.log`; run deployment again after SSM is online.
- **SSH fails**: check `enable_ssh`, `ssh_allowed_cidr`, key pair, and security group.
- **Changes are not visible**: hard refresh the browser. S3 website hosting has no CDN cache in this design.

## Cleanup

The bucket and EC2 instance have `prevent_destroy = true`. This is intentional. If you later want to remove these new resources, first review and back up the state, then deliberately remove `prevent_destroy` from the relevant module resources and run a reviewed `terraform plan`. Do not remove safeguards casually.
