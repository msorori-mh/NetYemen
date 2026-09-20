# NetYemen FCM Credential Prohibition Scan
# Task ID: NY-V1-PHYSICAL-PILOT-CLOSURE-001
# Description: Ensures no FCM server service-account private key material is
#              committed to the repository. Android google-services.json is
#              allowed, but must not contain a server private_key field.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$violations = @()

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen FCM Credential Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Enumerate candidate files (exclude build outputs and VCS metadata).
$candidates = Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/](\.git|\.dart_tool|build|android/\.gradle|android/app/build|supabase/\.branches|supabase/\.temp)[\\/]' -and
        $_.Extension -notin @('.lock', '.apk', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4', '.mp3')
    }

# 2. Detect real PEM private-key blocks. Reject placeholder examples like "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----".
$pemPattern = '(?s)-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----\s*(.+?)\s*-----END\s+(?:RSA\s+)?PRIVATE\s+KEY-----'
foreach ($file in $candidates) {
    try {
        $content = Get-Content -Raw -Path $file.FullName -ErrorAction Stop
    } catch {
        continue
    }
    if ([string]::IsNullOrWhiteSpace($content)) { continue }
    $pemMatches = [regex]::Matches($content, $pemPattern)
    foreach ($m in $pemMatches) {
        $inner = $m.Groups[1].Value.Trim()
        # Allow placeholder-only inner content (e.g. "...")
        if ($inner -eq '...' -or $inner -match '^\.{3,}$') { continue }
        # Any base64-looking content inside the PEM block is treated as real key material.
        if ($inner -match '[A-Za-z0-9+/=]{40,}') {
            $violations += "Real PEM private-key block found in $($file.FullName)"
            break
        }
    }
}

# 3. Detect Firebase service-account JSON fields (type == service_account + private_key).
$serviceAccountPattern = '"type"\s*:\s*"service_account"'
$privateKeyFieldPattern = '"private_key"\s*:\s*"'
foreach ($file in $candidates) {
    if ($file.Extension -notin @('.json', '.env', '.yaml', '.yml', '.toml', '.ps1', '.sh', '.ts', '.js', '.dart')) { continue }
    try {
        $content = Get-Content -Raw -Path $file.FullName -ErrorAction Stop
    } catch {
        continue
    }
    if ($content -match $serviceAccountPattern -and $content -match $privateKeyFieldPattern) {
        $violations += "Service-account JSON with private_key found in $($file.FullName)"
    }
}

# 4. android/app/google-services.json must not contain a server private_key field.
$googleServices = Join-Path $repoRoot 'android/app/google-services.json'
if (Test-Path $googleServices) {
    $gsContent = Get-Content -Raw -Path $googleServices
    if ($gsContent -match '"private_key"') {
        $violations += "android/app/google-services.json contains a server private_key field"
    }
} else {
    $violations += "android/app/google-services.json is missing"
}

# 5. Reject committed files named like service-account JSONs.
$serviceAccountFiles = Get-ChildItem -Path $repoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(?i)(service.?account|fcm.?service|firebase.?admin|sa_)\.*json$' }
foreach ($f in $serviceAccountFiles) {
    if ($f.FullName -notmatch '[\\/](\.git|build|\.dart_tool|android/\.gradle)[\\/]') {
        $violations += "Service-account JSON filename committed: $($f.FullName)"
    }
}

# 6. Report.
if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD (violations discovered)" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no FCM server private key material detected in repository)" -ForegroundColor Green
    exit 0
}
