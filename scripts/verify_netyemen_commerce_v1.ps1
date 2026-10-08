# NetYemen V1 Commerce Path Static Verification
# Task ID: NY-V1-COMMERCE-CORE-001
# Description: Runs static scans for secrets, card-secret prohibition, and financial invariants.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen V1 Commerce Path Static Verifier" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$scriptDir = $PSScriptRoot
$violations = @()

# Join-Path instead of "$scriptDir\name": a backslash is not a path separator
# on Linux/macOS, where CI runs this script.
$scans = @(
    @{ Name = "Secret Scan"; Script = (Join-Path $scriptDir "scan_netyemen_secrets.ps1") },
    @{ Name = "Card Secret Prohibition Scan"; Script = (Join-Path $scriptDir "scan_netyemen_card_secrets.ps1") },
    @{ Name = "Financial Invariant Scan"; Script = (Join-Path $scriptDir "scan_netyemen_financial_invariants.ps1") }
)

foreach ($scan in $scans) {
    Write-Host "Running $($scan.Name)..." -ForegroundColor Yellow
    try {
        # Reset first: a scan that ends without calling `exit` must not inherit
        # the exit code of an earlier command.
        $global:LASTEXITCODE = 0
        & $scan.Script | Out-Host
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $violations += "$($scan.Name) failed with exit code $exitCode"
        }
    } catch {
        $violations += "$($scan.Name) threw exception: $_"
    }
}

# Validate required commerce artifacts exist
$requiredArtifacts = @(
    "supabase/migrations/20260729095000_netyemen_commerce_core.sql",
    "supabase/tests/013_commerce_core.sql",
    "supabase/tests/026_settlement_refund_integrity.sql",
    "supabase/tests/027_purchase_card_ingest_integrity.sql",
    "docs/reports/NY-V1-COMMERCE-CORE-001-KIMI-REPORT.md"
)

foreach ($artifact in $requiredArtifacts) {
    $fullPath = Join-Path (Split-Path -Parent $scriptDir) $artifact
    if (-not (Test-Path $fullPath)) {
        $violations += "Required artifact missing: $artifact"
    } else {
        Write-Host "  [OK] $artifact" -ForegroundColor Green
    }
}

if ($violations.Count -gt 0) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "COMMERCE VERIFICATION RESULT: HOLD" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "COMMERCE VERIFICATION RESULT: PASS" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    exit 0
}
