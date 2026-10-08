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
$rawBranch = (git branch --show-current)
$currentBranch = if ($rawBranch) { $rawBranch.ToString().Trim() } else { "" }
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
# 5. Row-Level Security Enablement Verification (ALL migrations)
# -----------------------------------------------------------------------------
Write-Host "[5/8] Verifying Row-Level Security (RLS) Enablement..." -ForegroundColor Yellow
$coreTables = @("profiles", "user_roles", "networks", "network_memberships", "network_ssid_aliases", "audit_events")
$mig1Content = if (Test-Path $expectedMigrations[0]) { Get-Content $expectedMigrations[0] -Raw } else { "" }
$mig2Content = if (Test-Path $expectedMigrations[1]) { Get-Content $expectedMigrations[1] -Raw } else { "" }
# $combinedSql = the two core-foundation migrations only. It is still used by
# section 7, whose "no financial tables / object counts" rules are specific to
# the core foundation and would be wrong for later domain migrations.
$combinedSql = $mig1Content + "`n" + $mig2Content

# Every other security rule below runs over EVERY migration. Previously sections
# 5 and 6 inspected only the first two files, so a later migration could add a
# table without RLS, a permissive policy, GRANT ALL to a client role or a
# SECURITY DEFINER function without a pinned search_path and still pass.
$allMigrationFiles = @(Get-ChildItem -Path "supabase/migrations" -File -Filter *.sql | Sort-Object Name)
if ($allMigrationFiles.Count -eq 0) {
    $violations += "No migration files found under supabase/migrations (run this script from the repository root)."
}
$allSql = ""
foreach ($migrationFile in $allMigrationFiles) {
    $migrationSql = Get-Content -LiteralPath $migrationFile.FullName -Raw
    if (-not [string]::IsNullOrWhiteSpace($migrationSql)) {
        $allSql += $migrationSql + "`n"
    }
}
Write-Host "  Migrations inspected: $($allMigrationFiles.Count)" -ForegroundColor Cyan

foreach ($table in $coreTables) {
    $pattern = "(?i)ALTER\s+TABLE\s+public\.$table\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY"
    if ($allSql -notmatch $pattern) {
        $violations += "RLS not enabled on table public.$table"
    } else {
        Write-Host "  [OK] RLS Enabled for public.$table" -ForegroundColor Green
    }
}

# Every table created in the public schema by any migration must have RLS enabled
# by some migration.
$createdTables = @{}
foreach ($tableMatch in [regex]::Matches($allSql, '(?i)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.([a-z_0-9]+)')) {
    $createdTables[$tableMatch.Groups[1].Value.ToLowerInvariant()] = $true
}
$tablesWithoutRls = 0
foreach ($tableName in ($createdTables.Keys | Sort-Object)) {
    $rlsPattern = "(?i)ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?public\.$tableName\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY"
    if ($allSql -notmatch $rlsPattern) {
        $violations += "RLS not enabled on table public.$tableName"
        $tablesWithoutRls++
    }
}
Write-Host "  public tables created by migrations: $($createdTables.Count) (without RLS: $tablesWithoutRls)" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 6. Security Red Flags & Audit Write Locks Search (ALL migrations)
# -----------------------------------------------------------------------------
Write-Host "[6/8] Auditing Security Red Flags & Audit Write Locks..." -ForegroundColor Yellow

$grantAllAnyPattern = '(?i)(?<!REVOKE\s)GRANT\s+ALL\b'
$grantAllStatementPattern = '(?i)(?<!REVOKE\s)GRANT\s+ALL\b[^;]*?\bTO\s+([^;]+);'
$functionStartPattern = '(?i)CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([^\(\s]+)'

foreach ($migrationFile in $allMigrationFiles) {
    $migrationSql = Get-Content -LiteralPath $migrationFile.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($migrationSql)) { continue }
    $migrationName = $migrationFile.Name

    # GRANT ALL is acceptable only when every grantee is the trusted server
    # role service_role. Any other grantee (authenticated, anon, PUBLIC, ...)
    # is a red flag.
    $grantAllStatements = [regex]::Matches($migrationSql, $grantAllStatementPattern)
    foreach ($grantMatch in $grantAllStatements) {
        foreach ($grantee in $grantMatch.Groups[1].Value.Split(',')) {
            $granteeName = $grantee.Trim().ToLowerInvariant()
            if ($granteeName -ne "service_role") {
                $violations += "Security Red Flag: 'GRANT ALL' to '$granteeName' in $migrationName."
            }
        }
    }
    $grantAllCount = ([regex]::Matches($migrationSql, $grantAllAnyPattern)).Count
    if ($grantAllCount -ne $grantAllStatements.Count) {
        $violations += "Security Red Flag: 'GRANT ALL' statement in $migrationName could not be parsed (grantee unknown)."
    }

    # USING (FALSE) / WITH CHECK (FALSE) are deny-all and intentionally allowed.
    if ($migrationSql -match "(?i)USING\s*\(\s*true\s*\)") {
        $violations += "Security Warning: Permissive 'USING (true)' policy discovered in $migrationName."
    }
    if ($migrationSql -match "(?i)WITH\s+CHECK\s*\(\s*true\s*\)") {
        $violations += "Security Warning: Permissive 'WITH CHECK (true)' policy discovered in $migrationName."
    }

    # Verify audit write RPC (record_audit_event) is NOT granted to anon or authenticated
    if ($migrationSql -match "(?i)GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_audit_event[^\n;]*TO\s+[^;\n]*\b(authenticated|anon|public)\b") {
        $violations += "Security Red Flag: record_audit_event is granted to client roles (authenticated/anon/public) in $migrationName."
    }

    # Verify SECURITY DEFINER functions pin search_path. A function's text is
    # everything from its CREATE FUNCTION up to the next CREATE FUNCTION (or the
    # end of the file); this also covers functions that declare SECURITY DEFINER
    # after the body, which the previous single-statement regex could not see.
    $functionStarts = [regex]::Matches($migrationSql, $functionStartPattern)
    for ($functionIndex = 0; $functionIndex -lt $functionStarts.Count; $functionIndex++) {
        $chunkStart = $functionStarts[$functionIndex].Index
        $chunkEnd = $migrationSql.Length
        if (($functionIndex + 1) -lt $functionStarts.Count) {
            $chunkEnd = $functionStarts[$functionIndex + 1].Index
        }
        $functionChunk = $migrationSql.Substring($chunkStart, $chunkEnd - $chunkStart)
        if ($functionChunk -match "(?i)SECURITY\s+DEFINER" -and $functionChunk -notmatch "(?i)SET\s+search_path\s*(=|TO)") {
            $violations += "Security Red Flag: SECURITY DEFINER function missing fixed search_path: " + $functionStarts[$functionIndex].Groups[1].Value + " in $migrationName"
        }
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

# Machine-verifiable non-bypass role context checks for positive test harness
if ($posTestContent -notmatch "(?i)SET\s+LOCAL\s+ROLE\s+authenticated") {
    $violations += "Positive test harness lacks 'SET LOCAL ROLE authenticated' non-bypass switch."
} else {
    Write-Host "  [OK] Positive tests executed as authenticated." -ForegroundColor Green
}

if ($posTestContent -notmatch "(?i)SET\s+LOCAL\s+ROLE\s+anon") {
    $violations += "Positive test harness lacks 'SET LOCAL ROLE anon' non-bypass switch."
} else {
    Write-Host "  [OK] Anonymous tests executed as anon." -ForegroundColor Green
}

if ($posTestContent -notmatch "(?i)SET\s+LOCAL\s+ROLE\s+service_role") {
    $violations += "Positive test harness lacks 'SET LOCAL ROLE service_role' non-bypass switch."
} else {
    Write-Host "  [OK] Trusted audit test executed as service_role." -ForegroundColor Green
}

if ($posTestContent -notmatch "(?i)current_user\s*=\s*'authenticated'" -and $posTestContent -notmatch "(?i)current_user\s*!=\s*'authenticated'") {
    $violations += "Positive test harness lacks explicit current_user = 'authenticated' assertion."
}
if ($posTestContent -notmatch "(?i)current_user\s*=\s*'anon'" -and $posTestContent -notmatch "(?i)current_user\s*!=\s*'anon'") {
    $violations += "Positive test harness lacks explicit current_user = 'anon' assertion."
}
if ($posTestContent -notmatch "(?i)current_user\s*=\s*'service_role'" -and $posTestContent -notmatch "(?i)current_user\s*!=\s*'service_role'") {
    $violations += "Positive test harness lacks explicit current_user = 'service_role' assertion."
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
    Write-Host "  Migrations Scanned for Security Red Flags: $($allMigrationFiles.Count)" -ForegroundColor Green
    Write-Host "  Positive Tests : $posTestCount" -ForegroundColor Green
    Write-Host "  Negative Tests : $negTestCount" -ForegroundColor Green
    Write-Host "  Invariant Tests: $invTestCount" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    exit 0
}
