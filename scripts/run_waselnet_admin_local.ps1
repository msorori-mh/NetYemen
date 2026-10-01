param(
    [int]$Port = 7357
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$branch = 'kimi/NY-V1-EXTERNAL-PILOT-BINDING-001'
$projectRef = 'pgiidgoafajfpcnlmzde'
$supabaseUrl = "https://$projectRef.supabase.co"
$recoveryRedirectUrl = "http://localhost:$Port"
$publishableKey = $env:WASELNET_SUPABASE_PUBLISHABLE_KEY

if (-not [string]::IsNullOrWhiteSpace($publishableKey)) {
    $publishableKey = $publishableKey.Trim()
}

if ([string]::IsNullOrWhiteSpace($publishableKey)) {
    throw @'
HOLD: WASELNET_SUPABASE_PUBLISHABLE_KEY is not set.
Set it only in this PowerShell session, then rerun this script.
Do not paste the key into source code, GitHub, screenshots, or chat.
'@
}

# A legacy service_role key is also a JWT starting with "eyJ", so a prefix
# check is not enough: decode the payload and require role = anon.
function Test-LegacyAnonJwt {
    param([string]$Key)
    $parts = $Key.Split('.')
    if ($parts.Length -ne 3 -or -not $Key.StartsWith('eyJ')) { return $false }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        1 { return $false }
        2 { $payload += '==' }
        3 { $payload += '=' }
    }
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
    } catch {
        return $false
    }
    if ($null -eq $claims -or -not ($claims.PSObject.Properties.Name -contains 'role')) {
        return $false
    }
    return ($claims.role -ceq 'anon')
}

$isSecretKey = $publishableKey.StartsWith('sb_secret_')
$isPublishableKey = $publishableKey.StartsWith('sb_publishable_')
$isLegacyAnonJwt = Test-LegacyAnonJwt -Key $publishableKey
if ($isSecretKey -or -not ($isPublishableKey -or $isLegacyAnonJwt)) {
    throw @'
HOLD: WASELNET_SUPABASE_PUBLISHABLE_KEY is not a Supabase client key.
Copy the Publishable key (or legacy anon key) from Project Settings > API Keys.
Do not enter an account password, service-role key, or secret key.
'@
}

$currentBranch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $currentBranch -ne $branch) {
    throw "HOLD: Run from branch $branch. Current branch: $currentBranch"
}

& git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw 'HOLD: git fetch origin failed.'
}

$localHead = (& git rev-parse HEAD).Trim()
$remoteHead = (& git rev-parse "origin/$branch").Trim()
if ($LASTEXITCODE -ne 0) {
    throw "HOLD: Could not resolve origin/$branch."
}
if ($localHead -ne $remoteHead) {
    throw @"
HOLD: The local admin console is stale.
Local HEAD : $localHead
Remote HEAD: $remoteHead
Run:
  git merge --ff-only origin/$branch
Then rerun this script.
"@
}

& flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) {
    throw 'HOLD: flutter pub get --enforce-lockfile failed.'
}

Write-Host "Starting WASEL NET admin console from HEAD $localHead"
Write-Host "Auth project: $projectRef"
Write-Host "Recovery redirect: $recoveryRedirectUrl"
Write-Host 'The publishable key will not be printed.'

$flutterArgs = @(
    'run'
    '-d'
    'chrome'
    "--web-port=$Port"
    '--target=lib/admin_main.dart'
    "--dart-define=SUPABASE_URL=$supabaseUrl"
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
    "--dart-define=ADMIN_PASSWORD_RECOVERY_REDIRECT_URL=$recoveryRedirectUrl"
)
& flutter @flutterArgs

if ($LASTEXITCODE -ne 0) {
    throw 'HOLD: WASEL NET admin console exited with an error.'
}
