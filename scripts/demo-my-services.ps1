# Smoke test the *deployed gateway* and record created IDs for the personal demo.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = $BaseUrl.TrimEnd('/')
$stamp = (Get-Date -Format yyyyMMddHHmmss)
Write-Host "Testing public S24 gateway at $base"
$ins = Invoke-RestMethod -Method Post -Uri "$base/api/users" -ContentType 'application/json' -Body (@{name='Demo Instructor';email="instructor-$stamp@example.com";role='instructor'} | ConvertTo-Json)
$learner = Invoke-RestMethod -Method Post -Uri "$base/api/users" -ContentType 'application/json' -Body (@{name='Demo Learner';email="learner-$stamp@example.com";role='learner'} | ConvertTo-Json)
$headers = @{'X-User-Id' = [string]$ins.id}
$course = Invoke-RestMethod -Method Post -Uri "$base/api/courses" -Headers $headers -ContentType 'application/json' -Body (@{title='Cloud Computing Demo';description='S24 personal AWS demo';category='cloud computing';level='beginner'} | ConvertTo-Json)
$lesson = Invoke-RestMethod -Method Post -Uri "$base/api/courses/$($course.id)/lessons" -Headers $headers -ContentType 'application/json' -Body (@{title='Consistent hashing';duration_seconds=600} | ConvertTo-Json)
Write-Host "Instructor ID: $($ins.id)"
Write-Host "Learner ID:    $($learner.id)"
Write-Host "Course ID:     $($course.id)"
Write-Host "Lesson ID:     $($lesson.id)"
Write-Host "Open $base/ui/ for the browser demo. To verify RDS, use an EKS pod and the RDS host from Terraform output."
