# Personal AWS deployment — S24 Online Video Learning

This is a **separate practice copy** of the original project. It retains the actual
Terraform infrastructure, Python services, six Kubernetes workloads, ArgoCD,
MSK, Lambda, RDS, DynamoDB, S3 and EMR. It does not modify your friend's upstream.

**Status:** The sources have been checked and the account-switch scripts have been
added. **No live AWS deployment has been executed or verified.** Actual success
depends on account quotas, permissions, service versions, and regional availability.

## Before you start

- AWS CLI v2, Terraform >= 1.6, Docker Desktop (Linux containers), Git, kubectl,
  Helm, Python installed on Windows. `kubectl` and Helm are also useful for debugging.
- An AWS account with permissions to create EKS, EC2, VPC endpoints, RDS,
  DynamoDB, S3, MSK, Lambda, SQS, EMR, IAM, ECR and load balancers.
- **Your OWN separate PUBLIC GitHub repository**, e.g.
  `https://github.com/YOUR_USERNAME/s24-my-aws-demo.git`. Create this *empty*
  repository on GitHub first. Public is simplest for ArgoCD.
- Confirm your AWS CLI's active account belongs to you. If using profiles,
  set `$env:AWS_PROFILE='your-profile'` in the current PowerShell terminal.
- Confirm **EC2 standard On-Demand vCPU quota >= 8** for the default two `t3.large`
  worker nodes plus one `m5.xlarge` EMR master. Also check **EKS, MSK and EMR
  service limits, load balancer eligibility, supported EKS/Kafka/EMR versions and
  EC2 instance offerings in ap-south-1**. A new AWS account may be restricted.
- This stack is **NOT Free Tier**. It provisions EKS, multiple EC2 instances,
  RDS, MSK, EMR, VPC interface endpoints, load balancers and other resources.
  Charges start during provisioning and continue even if you close VS Code.
  The old README's `~$1/hour` is an unverified historical estimate, NOT a cap.
- Terraform state contains secrets. **Never commit/share** `terraform.tfvars`,
  `terraform.tfstate`, generated plan files, credentials or a private Git token.
- Allow more than the original README's 30–40 minute estimate: cloud API/quotas,
  Helm installs, image builds and first app stabilization can take longer.

## 1. Extract ZIP, open VS Code, confirm YOUR identity

Open the extracted `s24-online-video-learning-main` folder in VS Code.
In PowerShell:

```powershell
aws sts get-caller-identity
aws configure get region
terraform -version
docker info --format '{{.ServerVersion}}'
```

The AWS account ID **must be yours**. Never paste AWS secret access keys into chat
or scripts.

## 2. Configure this copy for your AWS account and own GitHub repository

From the project root (edit the two placeholders):

```powershell
.\scripts\prepare-personal-aws.ps1 `
  -GitHubRepoUrl "https://github.com/YOUR_USERNAME/s24-my-aws-demo.git" `
  -ExpectedAccountId "YOUR_12_DIGIT_AWS_ACCOUNT_ID" `
  -ProjectName "s24-personal" `
  -Region "ap-south-1"
```

If PowerShell blocks scripts, you can use a **process-scoped** policy in that
terminal: `Set-ExecutionPolicy -Scope Process Bypass` (only if you trust this copy).

The preparation script checks AWS STS identity **before writing**. It then creates
`terraform/terraform.tfvars` (git-ignored), writes **your own account ECR image
references** into `k8s-apps/overlays/aws/kustomization.yaml`, and updates
`argocd-app.yaml` to **your** GitHub URL. The initial `pending-first-build` image
is intentionally a placeholder; you will build and push the images after ECR
repositories exist. `prepare-personal-aws.ps1` does **not** provision AWS resources.
If you need to reconfigure an already prepared copy, inspect `terraform.tfvars`
before running the script again with `-Overwrite`.

## 3. Push ONLY your independent project copy to YOUR GitHub repository

From project root (not your friend's Git checkout):

```powershell
git init -b main
git add .
git status
# VERIFY that terraform.tfvars, .tfstate, AWS secrets etc. are NOT staged.
git commit -m "S24 personal AWS demo copy"
git remote add origin https://github.com/YOUR_USERNAME/s24-my-aws-demo.git
git push -u origin main
```

If `origin` already exists, **inspect it** with `git remote -v`. Do not replace it
until you know it points to your own repository. The PowerShell image script
refuses to push if `origin` does not match `terraform.tfvars` GitOps URL.

## 4. Inspect resource requirements before applying

```powershell
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region ap-south-1 --query "Quota.Value"
aws eks list-clusters --region ap-south-1
aws rds describe-db-instances --region ap-south-1 --query "DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]"
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=personal.tfplan
terraform -chdir=terraform show personal.tfplan
```

**STOP and inspect** the planned changes, permissions, resource sizes and cost.
The plan should refer to your `s24-personal` prefix and YOUR own AWS account.
If unfamiliar resources are scheduled for deletion or changes to an existing
team environment, do not apply. The default project attempts the *full* stack.

## 5. Provision the original full project infrastructure

Only if you deliberately accept the AWS charges and plan:

```powershell
terraform -chdir=terraform apply personal.tfplan
```

This is **not** a guaranteed one-pass deployment: new EKS clusters, MSK, EMR,
load balancers, Helm controllers, quotas, and Kubernetes/Helm provider bootstrapping
may produce actionable errors. Inspect errors and Terraform state, then reconcile
before any second plan/apply. **Do not run `destroy` on a different state or
repository.** ArgoCD may temporarily show `ImagePullBackOff` before Step 6,
because the images are not pushed yet.

Once provisioned:

```powershell
$region  = terraform -chdir=terraform output -raw aws_region
$cluster = terraform -chdir=terraform output -raw eks_cluster_name
aws eks update-kubeconfig --region $region --name $cluster
kubectl -n argocd get applications
kubectl -n s24 get pods
```

## 6. Build and push all SIX containerized services to YOUR ECR

With Docker Desktop running and the personal GitHub origin set:

```powershell
.\scripts\build-and-push.ps1 -PushGit
```

This PowerShell script replaces the original Bash-only build script for a
Windows demo. It reads *ECR registry + repository URLs from Terraform outputs*,
**verifies the current AWS account matches that registry**, builds six service
images, pushes them and updates only your GitOps overlay. The explicit
`-PushGit` flag commits and pushes the deployment pins to **your** repository.
ArgoCD then notices the Git change and syncs to your EKS cluster.

For later changes only to your two services:

```powershell
.\scripts\build-and-push.ps1 -Services user-service,catalog-service -PushGit
```

Verify:

```powershell
kubectl -n argocd get applications
kubectl -n s24 get pods,svc,hpa
kubectl -n s24 describe pods   # if workloads are not Ready
```

## 7. Reproduce your real demo (User Service, Catalog Service, three storages)

Find the ingress URL:

```powershell
$lb = kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
$BASE_URL = "http://$lb"
Write-Host "$BASE_URL/ui/"
```

If the load balancer hostname is empty, the cluster is not ready or your
AWS account lacks permission/eligibility. Inspect the service/events.

In a browser open `$BASE_URL/ui/` for the repository's actual Learning Console.
This connects to the published Content Delivery API, which routes calls to the
User and Catalog microservices on EKS.

For a quick PowerShell demonstration, create an instructor, learner, course and
lesson using the **real deployed gateway**:

```powershell
.\scripts\demo-my-services.ps1 -BaseUrl $BASE_URL
```

Verify PostgreSQL records from inside your EKS User Service pod (avoids exposing
the RDS endpoint publicly; this example reads credentials from the pod's injected
Kubernetes environment without printing them):

```powershell
kubectl -n s24 exec deploy/user-service -- python -c "import os,psycopg; c=psycopg.connect(host=os.environ['DB_HOST'],port=os.environ['DB_PORT'],dbname=os.environ['DB_NAME'],user=os.environ['DB_USER'],password=os.environ['DB_PASSWORD'],sslmode='require'); print(c.execute('SELECT name,email,role FROM users.learners LIMIT 5').fetchall()); c.close()"
```

Verify Terraform-created storage in your account:

```powershell
terraform -chdir=terraform output -raw rds_endpoint
terraform -chdir=terraform output -json dynamodb_tables
$bucket = terraform -chdir=terraform output -raw video_assets_bucket
aws s3 ls "s3://$bucket/" --region ap-south-1
aws dynamodb list-tables --region ap-south-1
```

For actual Requirement G proof, upload an MP4 through the learning console,
then check `videos/` in the S3 assets bucket. Submit learner progress in the
console and inspect `LearnerProgress` in DynamoDB. If the full Kafka/Flink/Lambda
pipeline is healthy, show the analytics/recommendations tables too.

## 8. Optional observability (required only if your demo includes it)

The repo's `observability/setup-commands.sh` is Bash and may require Git Bash,
Helm and kubectl. It installs monitoring via Helm *outside* Terraform; if your
assignment requires **all** infrastructure as IaC, address this compliance gap
rather than claiming the Helm script is in Terraform. See original `README.md`.

## 9. Tear down only YOUR personal AWS deployment

**Destroy resources soon after your demo to limit billing.** Take care not to
accidentally point Terraform at your friend's account or a different state.

First uninstall the optional monitoring Helm releases if installed (use Git Bash
or PowerShell Helm equivalents; check releases before removal). Then:

```powershell
aws sts get-caller-identity
terraform -chdir=terraform state list
terraform -chdir=terraform plan -destroy
# Review the destruction plan carefully:
terraform -chdir=terraform destroy
```

Type `yes` only after checking your account, project prefix and the resources
Terraform proposes to remove. Terraform may leave orphaned load balancers or
security groups if applications/controllers are still running; investigate those
before repeating cleanup. S3 objects and versioned contents can affect teardown.
**Never** run `terraform destroy` in your friend's original project directory.

## Limitations and notes

- This is the **actual full project structure**, with new per-account GitOps
  configuration and a Windows deployment path. It is **not tested on a live AWS
  account**. Terraform `validate` alone does not guarantee runtime success.
- All Terraform variables, including `eks_version = 1.35` and chart versions,
  remain as provided by the original repository. Verify regional availability.
- Some account-specific eligibility restrictions (especially Elastic Load
  Balancing, MSK, EMR) cannot be fixed just by editing project files.
- The first ArgoCD reconciliation will reference placeholder image tags until
  `build-and-push.ps1` successfully pushes new tags.
- A real 15-minute **presentation** is feasible after infrastructure is running;
  a clean cloud deployment of this full stack may take much longer.
