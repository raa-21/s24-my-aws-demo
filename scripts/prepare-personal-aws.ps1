# Run from any folder. Changes only THIS COPY's local Terraform inputs and GitOps manifests.
# Never creates AWS resources, changes Git remotes, or pushes to GitHub.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^https://github\.com/[^/]+/[^/]+(\.git)?$')]
    [string]$GitHubRepoUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,25}$')]
    [string]$ProjectName = 's24-personal',
    [string]$Region = 'ap-south-1',
    [switch]$Overwrite
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tfvarsPath = Join-Path $root 'terraform/terraform.tfvars'
$overlayPath = Join-Path $root 'k8s-apps/overlays/aws/kustomization.yaml'
$argoPath = Join-Path $root 'argocd-app.yaml'

if ((Test-Path $tfvarsPath) -and -not $Overwrite) {
    throw 'terraform/terraform.tfvars already exists. Inspect it before using -Overwrite. No files changed.'
}
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw 'AWS CLI not found. Install AWS CLI v2 and configure your own account first.'
}
$account = (& aws sts get-caller-identity --query Account --output text 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $account -notmatch '^[0-9]{12}$') {
    throw "AWS STS identity check failed: $account"
}
if ($account -ne $ExpectedAccountId) {
    throw "Account mismatch: AWS CLI reports $account, but you expected $ExpectedAccountId. No files changed."
}

$repoUrl = $GitHubRepoUrl.TrimEnd('/')
if (-not $repoUrl.EndsWith('.git')) { $repoUrl += '.git' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$tfvars = @"
# Local to this personal deployment. Ignored by Git. Never add access keys here.
aws_region = "$Region"
project_name = "$ProjectName"
environment = "demo"
gitops_repo_url = "$repoUrl"
gitops_repo_revision = "main"
"@

# Stage content in memory; update only after successful identity verification.
$services = @('user-service', 'catalog-service', 'metadata-service', 'content-delivery-api', 'cache-manager', 'progress-tracker')
$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('# Personal AWS copy. Initial image tags are placeholders until scripts/build-and-push.ps1 -PushGit completes.')
$lines.Add('apiVersion: kustomize.config.k8s.io/v1beta1')
$lines.Add('kind: Kustomization')
$lines.Add('resources:')
$lines.Add('  - ../../base')
$lines.Add('images:')
foreach ($service in $services) {
    $lines.Add("  - name: s24/$service")
    $lines.Add("    newName: ${account}.dkr.ecr.${Region}.amazonaws.com/${ProjectName}/$service")
    $lines.Add('    newTag: "pending-first-build"')
}
$oldArgo = [System.IO.File]::ReadAllText($argoPath)
if ($oldArgo -notmatch '(?m)^    repoURL:') { throw 'Cannot find repoURL in argocd-app.yaml. No files changed.' }
$newArgo = [regex]::Replace($oldArgo, '(?m)^    repoURL:.*$', "    repoURL: $repoUrl")

[System.IO.File]::WriteAllText($tfvarsPath, $tfvars + "`n", $utf8)
[System.IO.File]::WriteAllText($overlayPath, ($lines -join "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText($argoPath, $newArgo, $utf8)
Write-Host "Configured a personal AWS deployment copy:"
Write-Host "  Verified AWS account: $account"
Write-Host "  Region:               $Region"
Write-Host "  Project prefix:       $ProjectName"
Write-Host "  GitOps repository:    $repoUrl"
Write-Host 'Next: REVIEW these changes, push this copy to that repository, then run terraform plan. No AWS resources were created.'
