$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$violations = @()
$gradle = Get-Content 'android/app/build.gradle.kts' -Raw
$config = Get-Content 'lib/core/config/app_config.dart' -Raw
$profile = Get-Content 'lib/features/profile/presentation/profile_screen.dart' -Raw
$deletionUi = Get-Content 'lib/features/profile/presentation/legal_and_deletion_screens.dart' -Raw
$deletionSql = Get-Content 'supabase/migrations/20260822200000_netyemen_account_deletion_requests.sql' -Raw
$legalFunction = Get-Content 'supabase/functions/public-legal/index.ts' -Raw

if ($gradle -notmatch 'compileSdk\s*=\s*36') {
    $violations += 'Android compileSdk 36 is not pinned.'
}
if ($gradle -notmatch 'targetSdk\s*=\s*36') {
    $violations += 'Android targetSdk 36 is not pinned.'
}
if ($gradle -notmatch 'Release signing is required') {
    $violations += 'Fail-closed release signing guard is missing.'
}
if ($gradle -match 'release\s*\{[^}]*signingConfigs\.getByName\("debug"\)') {
    $violations += 'Release build falls back to the debug signing key.'
}
if ($config -notmatch 'PRIVACY_POLICY_URL' -or $config -notmatch 'ACCOUNT_DELETION_URL') {
    $violations += 'Public legal URL configuration is incomplete.'
}
if ($profile -notmatch 'AccountDeletionScreen' -or $profile -notmatch 'PrivacyPolicyScreen') {
    $violations += 'Profile navigation lacks privacy or account deletion.'
}
if ($deletionUi -notmatch 'request_my_account_deletion' -and
    (Get-Content 'lib/features/profile/data/account_deletion_repository.dart' -Raw) -notmatch 'request_my_account_deletion') {
    $violations += 'Mobile deletion flow is not bound to the guarded RPC.'
}
if ($deletionSql -notmatch 'ACCOUNT_DELETION_REQUESTED' -or
    $deletionSql -notmatch 'ALTER TABLE public\.account_deletion_requests FORCE ROW LEVEL SECURITY') {
    $violations += 'Deletion database audit or forced RLS guard is missing.'
}
if ($legalFunction -notmatch 'delete-account' -or
    $legalFunction -notmatch 'request_my_account_deletion') {
    $violations += 'External account deletion page is incomplete.'
}

if ($violations.Count -gt 0) {
    Write-Host 'WASEL NET RELEASE READINESS SOURCE SCAN: HOLD' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  [FAIL] $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'WASEL NET RELEASE READINESS SOURCE SCAN: PASS' -ForegroundColor Green
