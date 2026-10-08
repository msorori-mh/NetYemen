# NetYemen Card Secret Prohibition Scan
# Ensures no plaintext card/voucher secrets are stored in source or migrations.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Card Secret Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

# Repository root derived from this script's location (scripts/ -> repo root).
# The previous hard-coded Windows path did not exist on CI, so the scan matched
# zero files and still printed PASS.
$searchRoot = Split-Path -Parent $PSScriptRoot

# File categories to scan
$sqlFiles = @(Get-ChildItem -Path (Join-Path $searchRoot "supabase") -Recurse -File -Filter *.sql)
$dartFiles = @(Get-ChildItem -Path (Join-Path $searchRoot "lib") -Recurse -File -Filter *.dart)
$allFiles = @($sqlFiles) + @($dartFiles)

Write-Host "Scanning $($sqlFiles.Count) SQL files and $($dartFiles.Count) Dart files under $searchRoot"

# A scan that looked at nothing must never report PASS.
if ($sqlFiles.Count -eq 0 -or $dartFiles.Count -eq 0) {
    Write-Host "RESULT: HOLD (scan found $($sqlFiles.Count) SQL and $($dartFiles.Count) Dart files; expected both > 0)" -ForegroundColor Red
    exit 1
}

# Patterns indicating plaintext card/voucher storage (OD-CARD-01)
$cardSecretPatterns = @(
    'CREATE\s+TABLE[^;]*\bcards?\b[^;]*\bcard_number\b',
    'INSERT\s+INTO\s+\w*cards?\b[^;]*\b\d{8,}\b',
    'card_number\s*[=:]\s*[''"][0-9]{8,}[''"]',
    'voucher_code\s*[=:]\s*[''"][A-Za-z0-9]{8,}[''"]',
    'wifi_password\s*[=:]\s*[''"][^''"]{4,}[''"]',
    'pin\s*[=:]\s*[''"][0-9]{4,}[''"]',
    'secret_reference\s*[=:]\s*[''"][A-Za-z0-9]{8,}[''"]'
)

foreach ($file in $allFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { continue }

    foreach ($pattern in $cardSecretPatterns) {
        if ($content -match $pattern) {
            $violations += "$($file.FullName): matches prohibited plaintext card secret pattern '$pattern'"
        }
    }
}

# Ensure fulfillment_records has no column that stores plaintext secret payload
$fulfillmentFiles = $sqlFiles | Where-Object { $_.Name -match "fulfillment|purchase" }
foreach ($file in $fulfillmentFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { continue }
    if ($content -match "CREATE\s+TABLE[^;]*\bfulfillment_records\b[^;]*\b(secret_payload|plaintext_secret|card_pin|voucher_code)\b") {
        $violations += "$($file.FullName): fulfillment_records contains forbidden secret payload column"
    }
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD (OD-CARD-01 violation)" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no plaintext card/voucher secrets detected in $($allFiles.Count) files)" -ForegroundColor Green
    exit 0
}
