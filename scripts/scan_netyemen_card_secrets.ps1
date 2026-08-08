# NetYemen Card Secret Prohibition Scan
# Ensures no plaintext card/voucher secrets are stored in source or migrations.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Card Secret Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

$searchRoot = "C:/projects/NetYemen-kimi-commerce"

# File categories to scan
$sqlFiles = Get-ChildItem -Path "$searchRoot/supabase" -Recurse -Filter *.sql -ErrorAction SilentlyContinue
$dartFiles = Get-ChildItem -Path "$searchRoot/lib" -Recurse -Filter *.dart -ErrorAction SilentlyContinue
$allFiles = $sqlFiles + $dartFiles

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
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
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
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "CREATE\s+TABLE[^;]*\bfulfillment_records\b[^;]*\b(secret_payload|plaintext_secret|card_pin|voucher_code)\b") {
        $violations += "$($file.FullName): fulfillment_records contains forbidden secret payload column"
    }
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD (OD-CARD-01 violation)" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no plaintext card/voucher secrets detected)" -ForegroundColor Green
    exit 0
}
