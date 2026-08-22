$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (git status --porcelain) {
    throw 'HOLD: Build must run from a clean, reviewed release commit.'
}

$requiredEnvironment = @(
    'WASELNET_SUPABASE_URL',
    'WASELNET_SUPABASE_PUBLISHABLE_KEY',
    'WASELNET_PRIVACY_POLICY_URL',
    'WASELNET_ACCOUNT_DELETION_URL'
)

foreach ($name in $requiredEnvironment) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "HOLD: Missing required environment variable $name."
    }
}

$privacyUri = [Uri]$env:WASELNET_PRIVACY_POLICY_URL
$deletionUri = [Uri]$env:WASELNET_ACCOUNT_DELETION_URL
foreach ($uri in @($privacyUri, $deletionUri)) {
    if ($uri.Scheme -ne 'https' -or $uri.Host -in @('localhost', '127.0.0.1')) {
        throw "HOLD: Public legal URL must use non-local HTTPS: $uri"
    }
}

if (-not (Test-Path 'android/key.properties')) {
    throw 'HOLD: android/key.properties is missing. Copy key.properties.example and configure the private upload key locally.'
}

$signingValues = Get-Content 'android/key.properties' |
    Where-Object { $_ -match '^[^#=]+=.+' }
if ($signingValues.Count -lt 4) {
    throw 'HOLD: Android upload signing configuration is incomplete.'
}

flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'HOLD: Locked dependency install failed.' }

dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { throw 'HOLD: Dart formatting failed.' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'HOLD: Flutter analysis failed.' }

flutter test --timeout 2m
if ($LASTEXITCODE -ne 0) { throw 'HOLD: Flutter tests failed.' }

flutter build appbundle --release `
    --dart-define="SUPABASE_URL=$env:WASELNET_SUPABASE_URL" `
    --dart-define="SUPABASE_PUBLISHABLE_KEY=$env:WASELNET_SUPABASE_PUBLISHABLE_KEY" `
    --dart-define="PRIVACY_POLICY_URL=$env:WASELNET_PRIVACY_POLICY_URL" `
    --dart-define="ACCOUNT_DELETION_URL=$env:WASELNET_ACCOUNT_DELETION_URL"
if ($LASTEXITCODE -ne 0) { throw 'HOLD: Signed Android App Bundle failed.' }

$bundle = Resolve-Path 'build/app/outputs/bundle/release/app-release.aab'
$hash = Get-FileHash -Algorithm SHA256 $bundle

Write-Host 'WASEL NET GOOGLE PLAY BUNDLE: PASS' -ForegroundColor Green
Write-Host "Bundle: $($bundle.Path)"
Write-Host "SHA256: $($hash.Hash)"
