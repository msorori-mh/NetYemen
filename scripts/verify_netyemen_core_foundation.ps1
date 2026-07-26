# NetYemen Core Foundation Static Verification Script
# Task ID: NY-GOV-BE-001 / NY-GOV-BE-001C
# File: scripts/verify_netyemen_core_foundation.ps1
# Description: Performs static code and security verification on NetYemen core Supabase backend source.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Core Backend Foundation Static Verifier (NY-GOV-BE-001C)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

# -----------------------------------------------------------------------------
# 1. Branch Validation
# -----------------------------------------------------------------------------
$currentBranch = (git branch --show-current).Trim()
Write-Host "[1/8] Checking Git Branch: $currentBranch" -ForegroundColor Yellow
if ($currentBranch -eq "main") {
    $violations += "CRITICAL: Script must not be executed directly on 'main' branch."
}

# -----------------------------------------------------------------------------
# 2. Required Test Files & Governance Documents Validation
# -----------------------------------------------------------------------------
Write-Host "[2/8] Validating Required Files Non-Empty Integrity..." -ForegroundColor Yellow

$requiredTestFiles = @(
    "supabase/tests/001_core_schema_contract.sql",
    "supabase/tests/002_core_authorization_positive.sql",
    "supabase/tests/003_core_authorization_negative.sql",
    "supabase/tests/004_core_invariants.sql"
)

$requiredDocFiles = @(
    "docs/NETYEMEN-CORE-BACKEND-FOUNDATION-01-REPORT.md",
    "docs/NETYEMEN-CORE-BACKEND-MIGRATION-MANIFEST-01.md",
    "docs/adr/ADR-002-ROLE-AND-RLS-FOUNDATION.md",
    "docs/adr/ADR-003-NETWORK-MEMBERSHIP-AND-SSID-ALIASES.md",
    "docs/adr/ADR-004-IMMUTABLE-AUDIT-FOUNDATION.md"
)

$allRequiredFiles = $requiredTestFiles + $requiredDocFiles

foreach ($file in $allRequiredFiles) {
    if (-not (Test-Path $file)) {
        $violations += "Required file missing: $file"
    } else {
        $item = Get-Item $file
        $content = Get-Content $file -Raw
        if ($item.Length -eq 0 -or [string]::IsNullOrWhiteSpace($content)) {
            $violations += "Required file is empty or whitespace-only: $file (bytes=$($item.Length))"
        } else {
            $lineCount = (Get-Content $file).Count
            Write-Host "  [OK] $file | bytes=$($item.Length) | lines=$lineCount" -ForegroundColor Green
        }
    }
}

# -----------------------------------------------------------------------------
# 3. Migration Files Order and Existence
# -----------------------------------------------------------------------------
Write-Host "[3/8] Validating Migration Manifest Order..." -ForegroundColor Yellow
$expectedMigrations = @(
    "supabase/migrations/20260727090000_netyemen_core_identity_and_networks.sql",
    "supabase/migrations/20260727091000_netyemen_core_rls_and_audit.sql"
)

foreach ($mig in $expectedMigrations) {
    if (-not (Test-Path $mig)) {
        $violations += "Missing expected migration file: $mig"
    } else {
        $item = Get-Item $mig
        $content = Get-Content $mig -Raw
        if ($item.Length -eq 0 -or [string]::IsNullOrWhiteSpace($content)) {
            $violations += "Migration file is empty: $mig"
        } else {
            Write-Host "  [OK] Found migration: $mig | bytes=$($item.Length)" -ForegroundColor Green
        }
    }
}

# -----------------------------------------------------------------------------
# 4. Forbidden Deferred Terms Search in Migrations
# -----------------------------------------------------------------------------
Write-Host "[4/8] Checking for Forbidden Deferred V1.5/V2 Terms..." -ForegroundColor Yellow
$forbiddenTerms = @("merchant", "distributor", "telecom", "mobile_topup", "adsl", "p2p")

foreach ($mig in $expectedMigrations) {
    if (Test-Path $mig) {
        $content = Get-Content $mig -Raw
        foreach ($term in $forbiddenTerms) {
            if ($content -match "(?i)\b$term\b") {
                $violations += "Forbidden deferred term '$term' discovered in $mig"
            }
        }
    }
}

# -----------------------------------------------------------------------------
# 5. Row-Level Security Enablement Verification
# -----------------------------------------------------------------------------
Write-Host "[5/8] Verifying Row-Level Security (RLS) Enablement..." -ForegroundColor Yellow
$coreTables = @("profiles", "user_roles", "networks", "network_memberships", "network_ssid_aliases", "audit_events")
$mig1Content = if (Test-Path $expectedMigrations[0]) { Get-Content $expectedMigrations[0] -Raw } else { "" }
$mig2Content = if (Test-Path $expectedMigrations[1]) { Get-Content $expectedMigrations[1] -Raw } else { "" }
$combinedSql = $mig1Content + "`n" + $mig2Content

foreach ($table in $coreTables) {
    $pattern = "(?i)ALTER\s+TABLE\s+public\.$table\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY"
    if ($combinedSql -notmatch $pattern) {
        $violations += "RLS not enabled on table public.$table"
    } else {
        Write-Host "  [OK] RLS Enabled for public.$table" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 6. Security Red Flags & Audit Write Locks Search
# -----------------------------------------------------------------------------
Write-Host "[6/8] Auditing Security Red Flags & Audit Write Locks..." -ForegroundColor Yellow
if ($combinedSql -match "(?i)(?<!REVOKE\s)GRANT\s+ALL\b") {
    $violations += "Security Red Flag: 'GRANT ALL' discovered in migration SQL."
}
if ($combinedSql -match "(?i)USING\s*\(\s*true\s*\)") {
    $violations += "Security Warning: Permissive 'USING (true)' policy discovered."
}
if ($combinedSql -match "(?i)WITH\s+CHECK\s*\(\s*true\s*\)") {
    $violations += "Security Warning: Permissive 'WITH CHECK (true)' policy discovered."
}

# Verify audit write RPC (record_audit_event) is NOT granted to anon or authenticated
if ($combinedSql -match "(?i)GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_audit_event[^\n;]*TO\s+[^;\n]*\b(authenticated|anon|public)\b") {
    $violations += "Security Red Flag: record_audit_event is granted to client roles (authenticated/anon/public)."
}

# Verify SECURITY DEFINER functions set search_path
$secDefinerMatches = [regex]::Matches($combinedSql, "(?i)CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([^\(\s]+)[^;]+SECURITY\s+DEFINER[^;]+;")
foreach ($match in $secDefinerMatches) {
    if ($match.Value -notmatch "(?i)SET\s+search_path\s*=") {
        $violations += "Security Red Flag: SECURITY DEFINER function missing fixed search_path: " + $match.Groups[1].Value
    }
}

# -----------------------------------------------------------------------------
# 7. Absence of Deferred Objects & Test Harness Metrics Thresholds
# -----------------------------------------------------------------------------
Write-Host "[7/8] Verifying Test Metrics Minimum Thresholds & Invariants..." -ForegroundColor Yellow

$financialObjects = @("wallets", "wallet_ledger_entries", "cards", "card_batches", "purchases", "settlements", "deposit_requests")
foreach ($obj in $financialObjects) {
    if ($combinedSql -match "(?i)CREATE\s+TABLE[^\n]*\b$obj\b") {
        $violations += "Prohibited deferred domain table discovered: $obj"
    }
}

$tableCount    = ([regex]::Matches($combinedSql, "(?i)CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS")).Count
$functionCount = ([regex]::Matches($combinedSql, "(?i)CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION")).Count
$triggerCount  = ([regex]::Matches($combinedSql, "(?i)CREATE\s+TRIGGER")).Count
$policyCount   = ([regex]::Matches($combinedSql, "(?i)CREATE\s+POLICY")).Count
$indexCount    = ([regex]::Matches($combinedSql, "(?i)CREATE\s+(?:UNIQUE\s+)?INDEX")).Count

$posTestContent = if (Test-Path "supabase/tests/002_core_authorization_positive.sql") { Get-Content "supabase/tests/002_core_authorization_positive.sql" -Raw } else { "" }
$negTestContent = if (Test-Path "supabase/tests/003_core_authorization_negative.sql") { Get-Content "supabase/tests/003_core_authorization_negative.sql" -Raw } else { "" }
$invTestContent = if (Test-Path "supabase/tests/004_core_invariants.sql") { Get-Content "supabase/tests/004_core_invariants.sql" -Raw } else { "" }

$posTestCount = ([regex]::Matches($posTestContent, "(?i)Test\s+\d+:")).Count
$negTestCount = ([regex]::Matches($negTestContent, "(?i)NEG-\d+:")).Count
$invTestCount = ([regex]::Matches($invTestContent, "(?i)Invariant\s+\d+:")).Count

Write-Host "  Tables         : $tableCount" -ForegroundColor Cyan
Write-Host "  Functions      : $functionCount" -ForegroundColor Cyan
Write-Host "  Triggers       : $triggerCount" -ForegroundColor Cyan
Write-Host "  RLS Policies   : $policyCount" -ForegroundColor Cyan
Write-Host "  Indexes        : $indexCount" -ForegroundColor Cyan
Write-Host "  Positive Tests : $posTestCount (min: 10)" -ForegroundColor Cyan
Write-Host "  Negative Tests : $negTestCount (min: 18)" -ForegroundColor Cyan
Write-Host "  Invariant Tests: $invTestCount (min: 12)" -ForegroundColor Cyan

if ($posTestCount -lt 10) {
    $violations += "Positive test count ($posTestCount) is below minimum threshold (10)."
}
if ($negTestCount -lt 18) {
    $violations += "Negative test count ($negTestCount) is below minimum threshold (18)."
}
if ($invTestCount -lt 12) {
    $violations += "Invariant test count ($invTestCount) is below minimum threshold (12)."
}

# Verify required SUCCESS notices in test harnesses
if ($posTestContent -notmatch "SUCCESS: All \d+ Positive Authorization Tests Passed") {
    $violations += "002_core_authorization_positive.sql missing required SUCCESS notice."
}
if ($negTestContent -notmatch "SUCCESS: All \d+ Negative Authorization Tests Passed") {
    $violations += "003_core_authorization_negative.sql missing required SUCCESS notice."
}
if ($invTestContent -notmatch "SUCCESS: All \d+ Core Invariants Passed") {
    $violations += "004_core_invariants.sql missing required SUCCESS notice."
}

# -----------------------------------------------------------------------------
# 8. Summary & Exit Code
# -----------------------------------------------------------------------------
Write-Host "[8/8] Summary Assessment..." -ForegroundColor Yellow

if ($violations.Count -gt 0) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "STATIC VERIFICATION RESULT: HOLD (Violations Discovered)" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host "  [FAIL] $v" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "STATIC VERIFICATION RESULT: PASS (All Rules Satisfied)" -ForegroundColor Green
    Write-Host "  Files Verified : $($allRequiredFiles.Count + $expectedMigrations.Count)" -ForegroundColor Green
    Write-Host "  Positive Tests : $posTestCount" -ForegroundColor Green
    Write-Host "  Negative Tests : $negTestCount" -ForegroundColor Green
    Write-Host "  Invariant Tests: $invTestCount" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    exit 0
}
