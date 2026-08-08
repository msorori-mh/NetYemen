# NetYemen V1 Commerce Path Static Verification
# Task ID: NY-V1-COMMERCE-CORE-001
# Description: Runs static scans for secrets, card-secret prohibition, and financial invariants.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen V1 Commerce Path Static Verifier" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$violations = @()

$scans = @(
    @{ Name = "Secret Scan"; Script = "$scriptDir\scan_netyemen_secrets.ps1" },
    @{ Name = "Card Secret Prohibition Scan"; Script = "$scriptDir\scan_netyemen_card_secrets.ps1" },
    @{ Name = "Financial Invariant Scan"; Script = "$scriptDir\scan_netyemen_financial_invariants.ps1" }
)

foreach ($scan in $scans) {
    Write-Host "Running $($scan.Name)..." -ForegroundColor Yellow
    try {
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
    "supabase/tests/011_commerce_core.sql",
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
